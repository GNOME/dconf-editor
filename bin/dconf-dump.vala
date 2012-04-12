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

class DConfLoadState {
	public string[] keys;
	public Variant?[] vals;
	int n_keys;
	int i;

	public DConfLoadState (int n) {
		keys = new string[n + 1];
		vals = new Variant?[n];
		n_keys = n;
		i = 0;
	}

	public bool add (void *key, void *value) {
		assert (i < n_keys);

		keys[i] = (string) key;
		vals[i] = (Variant) value;
		i++;

		return false;
	}
}

void dconf_load (string[] args) throws Error {
	var dir = args[2];
	DConf.verify_dir (dir);

	var tree = new Tree<string, Variant> (strcmp);
	var kf = keyfile_from_stdin ();

	foreach (var group in kf.get_groups ()) {
		foreach (var key in kf.get_keys (group)) {
			var rel = (group == "/" ? "" : group + "/") + key;
			DConf.verify_rel_key (rel);
			tree.insert (rel, Variant.parse (null, kf.get_value (group, key)));
		}
	}

	DConfLoadState list = new DConfLoadState (tree.nnodes ());
	tree.foreach (list.add);

	var client = new DConf.Client ();
	client.write_many (dir, list.keys, list.vals);
}
