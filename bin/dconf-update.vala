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

	var parent_name = name.ndup (end);
	parent = table.lookup (parent_name);

	if (parent == null) {
		parent = table.insert (parent_name);
		parent.set_parent (get_parent (table, parent_name));
	}

	return parent;
}

Gvdb.HashTable read_directory (string dirname) throws GLib.Error {
	var table = new Gvdb.HashTable ();
	unowned string? name;

	table.insert ("/");

	var dir = Dir.open (dirname);
	while ((name = dir.read_name ()) != null) {
		var filename = Path.build_filename (dirname, name);

		var kf = new KeyFile ();

		try {
			kf.load_from_file (filename, KeyFileFlags.NONE);
		} catch (GLib.Error e) {
			stderr.printf ("%s: %s\n", filename, e.message);
			continue;
		}

		foreach (var group in kf.get_groups ()) {
			if (group.has_prefix ("/") || group.has_suffix ("/") || group.str ("//") != null) {
				stderr.printf ("%s: ignoring invalid group name: %s\n", filename, group);
				continue;
			}

			foreach (var key in kf.get_keys (group)) {
				if (key.str ("/") != null) {
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

	return table;
}

void maybe_update_from_directory (string dirname) throws GLib.Error {
	Posix.Stat dir_buf;

	if (Posix.stat (dirname, out dir_buf) == 0 && Posix.S_ISDIR (dir_buf.st_mode)) {
		Posix.Stat file_buf;

		var filename = dirname.ndup (dirname.length - 2);

		if (Posix.stat (filename, out file_buf) == 0 && file_buf.st_mtime > dir_buf.st_mtime) {
			return;
		}

		var table = read_directory (dirname);

		var fd = Posix.open (filename, Posix.O_WRONLY);

		if (fd < 0 && errno != Posix.EEXIST) {
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
			system_bus.emit_signal (null, "/" + Path.get_basename (filename), "ca.desrt.dconf.Writer", "Notify",
			                        new Variant ("(tsas)", (uint64) 0, "/", new VariantBuilder (STRING_ARRAY)));
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

void do_update () {
	try {
		update_all ("/etc/dconf/db");
	} catch (GLib.Error e) {
		stderr.printf ("fatal: %s\n", e.message);
	}
}

// vim:noet ts=4 sw=4
