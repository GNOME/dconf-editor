namespace DConf {
	[Compact]
	[CCode (cheader_filename = "dconf-engine.h")]
	class Engine {
		internal Engine (string? profile);
		internal EngineMessage write (string key, GLib.Variant? value) throws GLib.Error;
		internal GLib.Variant? read (string key);
		internal GLib.Variant? read_default (string key);
		internal GLib.Variant? read_no_default (string key);
		internal EngineMessage set_locked (string key, bool locked);
		internal string[] list (string dir, void*junk = null);
		internal static void set_service_func (ServiceFunc func);
		internal EngineMessage watch (string name);
		internal EngineMessage unwatch (string name);
	}

	struct EngineMessage {
		int bus_type;
		string destination;
		string object_path;
		string @interface;
		string method;
		bool tagged;
		GLib.VariantType reply_type;
		GLib.Variant body;
	}

	[CCode (has_target = false)]
	delegate GLib.Variant? ServiceFunc (EngineMessage dcem);
}

// vim:noet sw=4 ts=4
