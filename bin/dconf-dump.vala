void add_to_keyfile (KeyFile kf, DConf.Client client, string topdir, string? rel = "") {
	var this_dir = topdir + rel;
	string this_group;

	if (rel != "") {
		this_group = rel.slice (0, -1);
	} else {
		this_group = "/";
	}

	foreach (var item in client.list (this_dir)) {
		if (item.has_suffix ("/")) {
			add_to_keyfile (kf, client, topdir, rel + item);
		} else {
			var val = client.read (this_dir + item);

			if (val != null) {
				kf.set_value (this_group, item, val.print (true));
			}
		}
	}
}

void dconf_dump (string[] args) throws Error {
	var client = new DConf.Client ();
	var kf = new KeyFile ();
	var dir = args[2];

	DConf.verify_dir (dir);

	add_to_keyfile (kf, client, dir);
	print ("%s", kf.to_data ());
}

KeyFile keyfile_from_stdin () throws Error {
	unowned string? tmp;
	char buffer[1024];

	var s = new StringBuilder ();
	while ((tmp = stdin.gets (buffer)) != null) {
		s.append (tmp);
	}

	var kf = new KeyFile ();
	kf.load_from_data (s.str, s.len, 0);

	return kf;
}

void dconf_load (string[] args) throws Error {
	var dir = args[2];
	DConf.verify_dir (dir);

	var changeset = new DConf.Changeset ();
	var kf = keyfile_from_stdin ();

	foreach (var group in kf.get_groups ()) {
		foreach (var key in kf.get_keys (group)) {
			var path = dir + (group == "/" ? "" : group + "/") + key;
			DConf.verify_key (path);
			changeset.set (path, Variant.parse (null, kf.get_value (group, key)));
		}
	}

	var client = new DConf.Client ();
	client.change_sync (changeset);
}
