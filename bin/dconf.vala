/*
 * Copyright © 2010, 2011 Codethink Limited
 * Copyright © 2011 Canonical Limited
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

void show_help (bool requested, string? command) {
	var str = new StringBuilder ();
	string? description = null;
	string? synopsis = null;

	switch (command) {
		case null:
			break;

		case "help":
			description = "Print help";
			synopsis = "COMMAND";
			break;

		case "read":
			description = "Read the value of a key";
			synopsis = "KEY";
			break;

		case "list":
			description = "List the sub-keys and sub-dirs of a dir";
			synopsis = "DIR";
			break;

		case "write":
			description = "Write a new value to a key";
			synopsis = "KEY VALUE";
			break;

		case "reset":
			description = "Reset a key or dir.  -f is required for dirs.";
			synopsis = "[-f] PATH";
			break;

		case "update":
			description = "Update the system dconf databases";
			synopsis = "";
			break;

		case "watch":
			description = "Watch a path for key changes";
			synopsis = "PATH";
			break;

		case "dump":
			description = "Dump an entire subpath to stdout";
			synopsis = "DIR";
			break;

		case "load":
			description = "Populate a subpath from stdin";
			synopsis = "DIR";
			break;

		default:
			str.append_printf ("Unknown command '%s'\n\n", command);
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
  reset             Reset the value of a key or dir
  update            Update the system databases
  watch             Watch a path for changes
  dump              Dump an entire subpath to stdout
  load              Populate a subpath from stdin

Use 'dconf help COMMAND' to get detailed help.

""");
	} else {
		str.append ("Usage:\n");
		str.append_printf ("  dconf %s %s\n\n", command, synopsis);
		str.append_printf ("%s\n\n", description);

		if (synopsis != "") {
			str.append ("Arguments:\n");

			if ("COMMAND" in synopsis) {
				str.append ("  COMMAND   The (optional) command to explain\n");
			}

			if ("PATH" in synopsis) {
				str.append ("  PATH      Either a KEY or DIR\n");
			}

			if ("PATH" in synopsis || "KEY" in synopsis) {
				str.append ("  KEY       A key path (starting, but not ending with '/')\n");
			}

			if ("PATH" in synopsis || "DIR" in synopsis) {
				str.append ("  DIR       A directory path (starting and ending with '/')\n");
			}

			if ("VALUE" in synopsis) {
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
}

void dconf_help (string[] args) throws Error {
	show_help (true, args[2]);
}

void dconf_read (string?[] args) throws Error {
	var client = new DConf.Client ();
	var key = args[2];

	DConf.verify_key (key);

	var result = client.read (key);

	if (result != null) {
		print ("%s\n", result.print (true));
	}
}

void dconf_list (string?[] args) throws Error {
	var client = new DConf.Client ();
	var dir = args[2];

	DConf.verify_dir (dir);

	foreach (var item in client.list (dir)) {
		print ("%s\n", item);
	}
}

void dconf_write (string?[] args) throws Error {
	var client = new DConf.Client ();
	var key = args[2];
	var val = args[3];

	DConf.verify_key (key);

	client.write_sync (key, Variant.parse (null, val));
}

void dconf_reset (string?[] args) throws Error {
	var client = new DConf.Client ();
	bool force = false;
	var index = 2;

	if (args[index] == "-f") {
		force = true;
		index++;
	}

	var path = args[index];

	DConf.verify_path (path);

	if (DConf.is_dir (path) && !force) {
		throw new OptionError.FAILED ("-f must be given to (recursively) reset entire dirs");
	}

	client.write_sync (path, null);
}

void show_path (DConf.Client client, string path) {
	if (DConf.is_key (path)) {
		var value = client.read (path);

		print ("  %s\n", value != null ? value.print (true) : "unset");
	}
}

void watch_function (DConf.Client client, string path, string[] items, string? tag) {
	foreach (var item in items) {
		var full = path + item;
		print ("%s\n", full);
		show_path (client, full);
	}
	print ("\n");
}

void dconf_watch (string?[] args) throws Error {
	var client = new DConf.Client ();
	var path = args[2];

	DConf.verify_path (path);

	client.changed.connect (watch_function);
	client.watch_sync (path);

	new MainLoop (null, false).run ();
}

void dconf_blame (string?[] args) throws Error {
	var connection = Bus.get_sync (BusType.SESSION, null);
	var reply = connection.call_sync ("ca.desrt.dconf", "/ca/desrt/dconf", "ca.desrt.dconf.ServiceInfo", "Blame",
	                                  null, new VariantType ("(s)"), DBusCallFlags.NONE, -1, null);
	print ("%s", reply.get_child_value (0).get_string (null));
}

void dconf_complete (string[] args) throws Error {
	var suffix = args[2];
	var path = args[3];

	if (path == "") {
		print ("/\n");
		return;
	}

	if (path[0] == '/') {
		var client = new DConf.Client ();
		var last = 0;

		for (var i = 1; path[i] != '\0'; i++) {
			if (path[i] == '/') {
				last = i;
			}
		}

		var dir = path.substring (0, last + 1);
		foreach (var item in client.list (dir)) {
			var full_item = dir + item;

			if (full_item.has_prefix (path) && item.has_suffix (suffix)) {
				print ("%s%s\n", full_item, full_item.has_suffix ("/") ? "" : " ");
			}
		}
	}
}

delegate void Command (string[] args) throws Error;

struct CommandMapping {
	Command func;
	string name;

	public CommandMapping (string name, Command func) {
		this.name = name;
		this.func = func;
	}
}

int main (string[] args) {
	assert (args.length != 0);
	Environment.set_prgname (args[0]);

	Intl.setlocale (LocaleCategory.ALL, "");

	var map = new CommandMapping[] {
		CommandMapping ("help",      dconf_help),
		CommandMapping ("read",      dconf_read),
		CommandMapping ("list",      dconf_list),
		CommandMapping ("write",     dconf_write),
		CommandMapping ("reset",     dconf_reset),
		CommandMapping ("update",    dconf_update),
		CommandMapping ("watch",     dconf_watch),
		CommandMapping ("dump",      dconf_dump),
		CommandMapping ("load",      dconf_load),
		CommandMapping ("blame",     dconf_blame),
		CommandMapping ("_complete", dconf_complete)
	};

	try {
		if (args[1] == null) {
			throw new OptionError.FAILED ("no command specified");
		}

		foreach (var mapping in map) {
			if (mapping.name == args[1]) {
				mapping.func (args);
				return 0;
			}
		}

		throw new OptionError.FAILED ("unknown command %s", args[1]);
	} catch (Error e) {
		stderr.printf ("error: %s\n\n", e.message);
		show_help (false, args[1]);
		return 1;
	}
}
