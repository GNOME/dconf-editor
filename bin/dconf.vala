/*
 * Copyright © 2010 Codethink Limited
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

int dconf_help (bool requested, string? command) {
	var str = new StringBuilder ();
	string? description = null;
	string? synopsis = null;

	switch (command) {
		case null:
			break;

		case "help":
			description = "Print help";
			synopsis = "[COMMAND]";
			break;

		case "read":
			description = "Read the value of a key";
			synopsis = "[KEY]";
			break;

		case "list":
			description = "List the sub-keys and sub-dirs of a dir";
			synopsis = "[DIR]";
			break;

		case "write":
			description = "Write a new value to a key";
			synopsis = "[KEY] [VALUE]";
			break;

		case "update":
			description = "Update the system dconf databases";
			synopsis = "";
			break;

		case "lock":
			description = "Set a lock on a path";
			synopsis = "[PATH]";
			break;

		case "unlock":
			description = "Clear a lock on a path";
			synopsis = "[PATH]";
			break;

		case "watch":
			description = "Watch a path for key changes";
			synopsis = "[PATH]";
			break;

		default:
			str.printf ("Unknown command %s\n\n", command);
			requested = false;
			command = null;
			break;
	}

	if (command == null) {
		str.append (
"""Usage:
  dconf COMMAND [ARGS...]

Commands:
  help              Show this information
  read              Read the value of a key
  list              List the contents of a dir
  write             Change the value of a key
  update            Update the system databases
  lock              Set a lock on a path
  unlock            Clear a lock on a path
  watch             Watch a path for changes

Use 'dconf help [COMMAND]' to get detailed help.

""");
	} else {
		str.append ("Usage:\n");
		str.printf ("  dconf %s %s\n\n", command, synopsis);
		str.printf ("%s\n\n", description);

		if (synopsis != "") {
			str.append ("Arguments:\n");

			if ("[COMMAND]" in synopsis) {
				str.append ("  COMMAND   The (optional) command to explain\n");
			}

			if ("[PATH]" in synopsis) {
				str.append ("  PATH      Either a KEY or DIR\n");
			}

			if ("[PATH]" in synopsis || "[KEY]" in synopsis) {
				str.append ("  KEY       A key path (starting, but not ending with '/')\n");
			}

			if ("[PATH]" in synopsis || "[DIR]" in synopsis) {
				str.append ("  DIR       A directory path (starting and ending with '/')\n");
			}

			if ("[VALUE]" in synopsis) {
				str.append ("  VALUE     The value to write (in GVariant format)\n");
			}
		}

		str.append ("\n");
	}

	if (requested) {
		print ("%s", str.str);
	} else {
		printerr ("%s", str.str);
	}

	return requested ? 0 : 1;
}

void do_read (DConf.Client client, string key) throws Error {
	DConf.verify_key (key);

	var result = client.read (key);
	if (result != null) {
		stdout.puts (result.print (true));
		stdout.putc ('\n');
	}
}

void do_list (DConf.Client client, string dir) throws Error {
	DConf.verify_dir (dir);

	foreach (var item in client.list (dir)) {
		stdout.puts (item);
		stdout.putc ('\n');
	}
}

void do_write (DConf.Client client, string key, string val) throws Error {
	DConf.verify_key (key);

	client.write (key, Variant.parse (null, val));
}

void do_lock (DConf.Client client, string key, bool locked) throws Error {
	DConf.verify_key (key);

	client.set_locked (key, locked);
}

void do_watch (DConf.Client client, string name) throws Error {
	DConf.verify_path (name);

	client.watch (name);
	new MainLoop (null, false).run ();
}

void main (string[] args) {
	try {
		var client = new DConf.Client ();

		Environment.set_prgname (args[0]);

		switch (args[1]) {
			case "help":
				dconf_help (true, args[2]);
				break;

			case "read":
				do_read (client, args[2]);
				break;

			case "list":
				do_list (client, args[2]);
				break;

			case "write":
				do_write (client, args[2], args[3]);
				break;

			case "update":
				do_update ();
				break;

			case "lock":
				do_lock (client, args[2], true);
				break;

			case "unlock":
				do_lock (client, args[2], false);
				break;

			case "watch":
				do_watch (client, args[2]);
				break;

			default:
				dconf_help (false, args[1]);
				break;
		}
	} catch (Error e) {
		stderr.printf ("error: %s\n", e.message);
	}
}

// vim:noet sw=4 ts=4
