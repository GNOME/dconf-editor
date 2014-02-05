/*
 * Copyright © 2010 Codethink Limited
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the licence, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, see <http://www.gnu.org/licenses/>.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 */

unowned Gvdb.Item get_parent (Gvdb.HashTable table, string name) {
	unowned Gvdb.Item parent;

	int end = 0;

	for (int i = 1; name[i] != '\0'; i++) {
		if (name[i - 1] == '/') {
			end = i;
		}
	}

	assert (end != 0);

	var parent_name = name.substring (0, end);
	parent = table.lookup (parent_name);

	if (parent == null) {
		parent = table.insert (parent_name);
		parent.set_parent (get_parent (table, parent_name));
	}

	return parent;
}

SList<string>? list_directory (string dirname, Posix.mode_t mode) throws GLib.Error {
	var list = new SList<string> ();
	var dir = Dir.open (dirname);
	unowned string? name;

	while ((name = dir.read_name ()) != null) {
		if (name.has_prefix (".")) {
			continue;
		}

		var filename = Path.build_filename (dirname, name);
		Posix.Stat buf;

		// only files of the requested type
		if (Posix.stat (filename, out buf) < 0 || (buf.st_mode & Posix.S_IFMT) != mode) {
			continue;
		}

		list.prepend (filename);
	}

	return list;
}

Gvdb.HashTable? read_locks_directory (string dirname) throws GLib.Error {
	SList<string>? files;

	try {
		files = list_directory (dirname, Posix.S_IFREG);
	} catch (FileError.NOENT e) {
		/* If locks directory is missing, there are just no locks... */
		return null;
	}

	var table = new Gvdb.HashTable ();

	foreach (var filename in files) {
		string contents;
		FileUtils.get_contents (filename, out contents, null);

		foreach (var line in contents.split ("\n")) {
			if (line.has_prefix ("/")) {
				table.insert_string (line, "");
			}
		}
	}

	return table;
}

Gvdb.HashTable read_directory (string dirname) throws GLib.Error {
	var table = new Gvdb.HashTable ();
	table.insert ("/");

	var files = list_directory (dirname, Posix.S_IFREG);
	files.sort (strcmp);
	files.reverse ();

	foreach (var filename in files) {
		var kf = new KeyFile ();

		try {
			kf.load_from_file (filename, KeyFileFlags.NONE);
		} catch (GLib.Error e) {
			e.message = "warning: Failed to read keyfile '%s': %s".printf (filename, e.message);
			throw e;
		}

		try {
			foreach (var group in kf.get_groups ()) {
				if (group.has_prefix ("/") || group.has_suffix ("/") || "//" in group) {
					stderr.printf ("%s: ignoring invalid group name: %s\n", filename, group);
					continue;
				}

				foreach (var key in kf.get_keys (group)) {
					if ("/" in key) {
						throw new KeyFileError.INVALID_VALUE ("%s: [%s]: invalid key name: %s",
						                                      filename, group, key);
					}

					var path = "/" + group + "/" + key;

					if (table.lookup (path) != null) {
						/* We process the files in reverse alphabetical order.  If the key is already set then
						 * it must have been set from a file with higher precedence so we should ignore this
						 * one.
						 */
						continue;
					}

					var text = kf.get_value (group, key);

					try {
						var value = Variant.parse (null, text);
						unowned Gvdb.Item item = table.insert (path);
						item.set_parent (get_parent (table, path));
						item.set_value (value);
					} catch (VariantParseError e) {
						e.message = "%s: [%s]: %s: invalid value: %s (%s)".printf (filename, group, key, text, e.message);
						throw e;
					}
				}
			}
		} catch (KeyFileError e) {
			/* This should never happen... */
			warning ("unexpected keyfile error: %s.  Please file a bug.", e.message);
			assert_not_reached ();
		}
	}

	var locks = read_locks_directory (dirname + "/locks");

	if (locks != null) {
		unowned Gvdb.Item item = table.insert (".locks");
		item.set_hash_table (locks);
	}

	return table;
}

void maybe_update_from_directory (string dirname) throws GLib.Error {
	Posix.Stat dir_buf;

	if (Posix.stat (dirname, out dir_buf) == 0 && Posix.S_ISDIR (dir_buf.st_mode)) {
		Posix.Stat lockdir_buf;
		Posix.Stat file_buf;

		var filename = dirname.substring (0, dirname.length - 2);

		if (Posix.stat (dirname + "/locks", out lockdir_buf) == 0 && lockdir_buf.st_mtime > dir_buf.st_mtime) {
			// if the lock directory has been updated more recently then consider its timestamp instead
			dir_buf.st_mtime = lockdir_buf.st_mtime;
		}

		if (Posix.stat (filename, out file_buf) == 0 && file_buf.st_mtime > dir_buf.st_mtime) {
			return;
		}

		var table = read_directory (dirname);

		var fd = Posix.open (filename, Posix.O_WRONLY);

		if (fd < 0 && errno != Posix.ENOENT) {
			var saved_error = errno;
			printerr ("warning: Failed to open '%s' for replacement: %s\n", filename, strerror (saved_error));
			return;
		}

		// We expect that fd < 0 here if ENOENT (ie: the db merely didn't exist yet)

		try {
			table.write_contents (filename);

			if (fd >= 0) {
				Posix.write (fd, "\0\0\0\0\0\0\0\0", 8);
			}
		} catch (Error e) {
			printerr ("warning: %s\n", e.message);
			return;
		} finally {
			if (fd >= 0) {
				Posix.close (fd);
			}
		}

		try {
			var system_bus = Bus.get_sync (BusType.SYSTEM);
			system_bus.emit_signal (null, "/ca/desrt/dconf/Writer/" + Path.get_basename (filename),
			                        "ca.desrt.dconf.Writer", "WritabilityNotify", new Variant ("(s)", "/"));
			system_bus.flush_sync ();
		} catch {
			/* if we can't, ... don't. */
		}
	}
}

void update_all (string dirname) throws GLib.Error {
	foreach (var name in list_directory (dirname, Posix.S_IFDIR)) {
		if (name.has_suffix (".d")) {
			try {
				maybe_update_from_directory (name);
			} catch (Error e) {
				printerr ("unable compile %s: %s\n", name, e.message);
			}
		}
	}
}

void dconf_compile (string[] args) throws GLib.Error {
	if (args[2] == null || args[3] == null || args[4] != null) {
			throw new OptionError.FAILED ("must give output file and .d dir");
	}

	try {
		// We always write the result of "dconf compile" as little endian
		// so that it can be installed in /usr/share
		var table = read_directory (args[3]);
		var should_byteswap = (BYTE_ORDER == ByteOrder.BIG_ENDIAN);
		table.write_contents (args[2], should_byteswap);
	} catch (Error e) {
		printerr ("%s\n", e.message);
		Process.exit (1);
	}
}

void dconf_update (string[] args) throws GLib.Error {
	update_all ("/etc/dconf/db");
}

// vim:noet ts=4 sw=4
