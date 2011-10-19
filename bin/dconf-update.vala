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
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 */

unowned Gvdb.Item get_parent (Gvdb.HashTable table, string name) {
	unowned Gvdb.Item parent;

	int end = 0;

	for (int i = 0; name[i] != '\0'; i++) {
		if (name[i - 1] == '/') {
			end = i;
		}
	}

	var parent_name = name.substring (0, end);
	parent = table.lookup (parent_name);

	if (parent == null) {
		parent = table.insert (parent_name);
		parent.set_parent (get_parent (table, parent_name));
	}

	return parent;
}

Gvdb.HashTable? read_locks_directory (string dirname) throws GLib.Error {
	Dir dir;

	try {
		dir = Dir.open (dirname);
	} catch {
		return null;
	}

	var table = new Gvdb.HashTable ();
	unowned string? name;

	while ((name = dir.read_name ()) != null) {
		var filename = Path.build_filename (dirname, name);
		Posix.Stat buf;

		// only 'normal' files
		if (Posix.stat (filename, out buf) < 0 || !Posix.S_ISREG (buf.st_mode)) {
			continue;
		}

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
	unowned string? name;

	table.insert ("/");

	var dir = Dir.open (dirname);
	while ((name = dir.read_name ()) != null) {
		var filename = Path.build_filename (dirname, name);
		Posix.Stat buf;

		// only 'normal' files
		if (Posix.stat (filename, out buf) < 0 || !Posix.S_ISREG (buf.st_mode)) {
			continue;
		}

		var kf = new KeyFile ();

		try {
			kf.load_from_file (filename, KeyFileFlags.NONE);
		} catch (GLib.Error e) {
			stderr.printf ("%s: %s\n", filename, e.message);
			continue;
		}

		foreach (var group in kf.get_groups ()) {
			if (group.has_prefix ("/") || group.has_suffix ("/") || "//" in group) {
				stderr.printf ("%s: ignoring invalid group name: %s\n", filename, group);
				continue;
			}

			foreach (var key in kf.get_keys (group)) {
				if ("/" in key) {
					stderr.printf ("%s: [%s]: ignoring invalid key name: %s\n", filename, group, key);
					continue;
				}

				var path = "/" + group + "/" + key;

				if (table.lookup (path) != null) {
					stderr.printf ("%s: [%s]: %s: ignoring duplicate definition of key %s\n",
					               filename, group, key, path);
					continue;
				}

				var text = kf.get_value (group, key);

				try {
					var value = Variant.parse (null, text);
					unowned Gvdb.Item item = table.insert (path);
					item.set_parent (get_parent (table, path));
					item.set_value (value);
				} catch (VariantParseError e) {
					stderr.printf ("%s: [%s]: %s: skipping invalid value: %s (%s)\n",
					               filename, group, key, text, e.message);
				}
			}
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
			throw new FileError.FAILED ("Can not open '%s' for replacement: %s", filename, strerror (saved_error));
		}

		try {
			table.write_contents (filename);

			if (fd >= 0) {
				Posix.write (fd, "\0\0\0\0\0\0\0\0", 8);
			}
		} finally {
			if (fd >= 0) {
				Posix.close (fd);
			}
		}

		try {
			var system_bus = Bus.get_sync (BusType.SYSTEM);
			system_bus.emit_signal (null, "/ca/desrt/dconf/Writer/" + Path.get_basename (filename), "ca.desrt.dconf.Writer",
			                        "WritabilityNotify", new Variant ("(s)", "/"));
			flush_the_bus (system_bus);
		} catch {
			/* if we can't, ... don't. */
		}
	}
}

void update_all (string dirname) throws GLib.Error {
	unowned string? name;

	var dir = Dir.open (dirname);

	while ((name = dir.read_name ()) != null) {
		if (name.has_suffix (".d")) {
			try {
				maybe_update_from_directory (Path.build_filename (dirname, name));
			} catch (GLib.Error e) {
				stderr.printf ("%s\n", e.message);
			}
		}
	}
}

void dconf_update (string[] args) {
	try {
		update_all ("/etc/dconf/db");
	} catch (GLib.Error e) {
		stderr.printf ("fatal: %s\n", e.message);
	}
}

// vim:noet ts=4 sw=4
