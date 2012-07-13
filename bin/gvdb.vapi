[CCode (cheader_filename = "../gvdb/gvdb-builder.h")]
namespace Gvdb {
	[Compact]
	[CCode (cname = "GHashTable")]
	class HashTable : GLib.HashTable<string, Item> {
		public HashTable (HashTable? parent = null, string? key = null);
		public unowned Item insert (string key);
		public void insert_string (string key, string value);
		[CCode (cname = "gvdb_table_write_contents")]
		public void write_contents (string filename, bool byteswap = false) throws GLib.Error;
	}

	[Compact]
	class Item {
		public void set_value (GLib.Variant value);
		public void set_hash_table (HashTable table);
		public void set_parent (Item parent);
	}
}

// vim:noet ts=4 sw=4
