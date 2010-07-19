

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

void main (string[] args) {
	try {
		var client = new DConf.Client ();

		Environment.set_prgname (args[0]);

		switch (args[1]) {
			case "read":
				do_read (client, args[2]);
				break;

			case "list":
				do_list (client, args[2]);
				break;

			case "write":
				do_write (client, args[2], args[3]);
				break;

			default:
				error ("unknown command");
				break;
		}
	} catch (Error e) {
		stderr.printf ("error: %s\n", e.message);
	}
}

// vim:noet sw=4 ts=4
