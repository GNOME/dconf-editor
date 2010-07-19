[CCode (cheader_filename = "dconf.h")]
namespace DConf {
	public delegate void WatchFunc (DConf.Client client, string path, string[] items, string tag);

	public class Client : Object {
		Engine engine;
		WatchFunc watch_func;

		static BusType get_bus_type (EngineMessage dcem) {
			switch (dcem.bus_type) {
				case 'e':
					return BusType.SESSION;
				case 'y':
					return BusType.SYSTEM;
				default:
					assert_not_reached ();
			}
		}

		void call_sync (EngineMessage dcem, out string tag, Cancellable? cancellable) throws Error {
			var connection = Bus.get_sync (get_bus_type (dcem), cancellable);

			foreach (var message in dcem.body) {
				var reply = connection.call_sync (dcem.destination, dcem.object_path, dcem.@interface, dcem.method,
				                                  message, dcem.reply_type, DBusCallFlags.NONE, -1, cancellable);
				if (dcem.tagged) {
					reply.get ("(s)", out tag);
				}
			}
		}

		async void call_async (EngineMessage dcem, out string tag, Cancellable? cancellable) throws Error {
			var connection = yield Bus.get (get_bus_type (dcem), cancellable);

			foreach (var message in dcem.body) {
				var reply = yield connection.call (dcem.destination, dcem.object_path, dcem.@interface, dcem.method,
				                                   message, dcem.reply_type, DBusCallFlags.NONE, -1, cancellable);
				if (dcem.tagged) {
					reply.get ("(s)", out tag);
				}
			}
		}

		public bool write (string key, Variant? value, out string tag = null, Cancellable? cancellable = null) throws Error {
			if (&tag == null) { /* bgo #591673 */
				string junk;
				call_sync (engine.write (key, value), out junk, cancellable);
			} else {
				call_sync (engine.write (key, value), out tag, cancellable);
			}
			return true;
		}

		public async bool write_async (string key, Variant? value, out string tag = null, Cancellable? cancellable = null) throws Error {
			yield call_async (engine.write (key, value), out tag, cancellable);
			return true;
		}

		public bool set_lock (string key, bool locked, Cancellable? cancellable = null) throws Error {
			call_sync (engine.set_lock (key, locked), null, cancellable);
			return true;
		}

		public async bool set_lock_async (string key, bool locked, Cancellable? cancellable = null) throws Error {
			yield call_async (engine.set_lock (key, locked), null, cancellable);
			return true;
		}

		public Variant? read (string key) {
			return engine.read (key);
		}

		public Variant? read_default (string key) {
			return engine.read_default (key);
		}

		public Variant? read_no_default (string key) {
			return engine.read_no_default (key);
		}

		public string[] list (string dir) {
			return engine.list (dir);
		}

		public bool watch (string name, Cancellable? cancellable = null) throws GLib.Error {
			call_sync (engine.watch (name), null, cancellable);
			return true;
		}

		public async bool watch_async (string name, Cancellable? cancellable = null) throws GLib.Error {
			yield call_async (engine.watch (name), null, cancellable);
			return true;
		}

		public bool unwatch (string name, Cancellable? cancellable = null) throws GLib.Error {
			call_sync (engine.unwatch (name), null, cancellable);
			return true;
		}

		public async bool unwatch_async (string name, Cancellable? cancellable = null) throws GLib.Error {
			yield call_async (engine.unwatch (name), null, cancellable);
			return true;
		}

		static Variant? service_func (EngineMessage dcem) {
			try {
				var connection = Bus.get_sync (get_bus_type (dcem), null);
				return connection.call_sync (dcem.destination, dcem.object_path, dcem.@interface, dcem.method,
				                             dcem.body, dcem.reply_type, DBusCallFlags.NONE, -1, null);
			} catch {
				return null;
			}
		}

		public Client (string? profile = null, owned WatchFunc? watch_func = null) {
			Engine.set_service_func (service_func);

			engine = new Engine (profile);
			this.watch_func = watch_func;
		}
	}

	public extern bool is_path (string str, Error *error = null);
	public extern bool is_key (string str, Error *error = null);
	public extern bool is_dir (string str, Error *error = null);
	public extern bool is_rel_path (string str, Error *error = null);
	public extern bool is_rel_key (string str, Error *error = null);
	public extern bool is_rel_dir (string str, Error *error = null);
	[CCode (cname = "dconf_is_path")]
	public extern bool verify_path (string str) throws Error;
	[CCode (cname = "dconf_is_key")]
	public extern bool verify_key (string str) throws Error;
	[CCode (cname = "dconf_is_dir")]
	public extern bool verify_dir (string str) throws Error;
	[CCode (cname = "dconf_is_rel_path")]
	public extern bool verify_rel_path (string str) throws Error;
	[CCode (cname = "dconf_is_rel_key")]
	public extern bool verify_rel_key (string str) throws Error;
	[CCode (cname = "dconf_is_rel_dir")]
	public extern bool verify_rel_dir (string str) throws Error;
}

// vim:noet sw=4 ts=4
