[CCode (cheader_filename = "dconf.h")]
namespace DConf {
	public delegate void WatchFunc (DConf.Client client, string path, string[] items, string tag);

	public class Client : Object {
		DBusConnection? session;
		DBusConnection? system;
		WatchFunc watch_func;
		Engine engine;

		void call_sync (EngineMessage dcem, out string tag, Cancellable? cancellable) throws Error {
			DBusConnection connection;

			if (dcem.bus_type == 'e') {
				if (session == null) {
					session = Bus.get_sync (BusType.SESSION, cancellable);
				}
				connection = session;
			} else {
				assert (dcem.bus_type == 'y');
				if (system == null) {
					system = Bus.get_sync (BusType.SYSTEM, cancellable);
				}
				connection = system;
			}

			foreach (var message in dcem.body) {
				var reply = connection.call_sync (dcem.destination, dcem.object_path, dcem.@interface, dcem.method,
				                                  message, dcem.reply_type, DBusCallFlags.NONE, -1, cancellable);
				if (dcem.tagged) {
					reply.get ("(s)", out tag);
				}
			}
		}

		async void call_async (EngineMessage dcem, out string tag, Cancellable? cancellable) throws Error {
			DBusConnection connection;

			if (dcem.bus_type == 'e') {
				if (session == null) {
					session = yield Bus.get (BusType.SESSION, cancellable);
				}
				connection = session;
			} else {
				assert (dcem.bus_type == 'y');
				if (system == null) {
					system = yield Bus.get (BusType.SYSTEM, cancellable);
				}
				connection = system;
			}

			foreach (var message in dcem.body) {
				var reply = yield connection.call (dcem.destination, dcem.object_path, dcem.@interface, dcem.method,
				                                   message, dcem.reply_type, DBusCallFlags.NONE, -1, cancellable);
				if (dcem.tagged) {
					reply.get ("(s)", out tag);
				}
			}
		}

		/**
		 * dconf_client_write:
		 * @client: a #DConfClient
		 * @key: a dconf key
		 * @value: (allow-none): a #GVariant, or %NULL
		 * @tag: (out) (allow-none): the tag from this write
		 * @cancellable: a #GCancellable, or %NULL
		 * @error: a pointer to a #GError, or %NULL
		 * @returns: %TRUE if the write is successful
		 *
		 * Write a value to the given @key, or reset @key to its default value.
		 *
		 * If @value is %NULL then @key is reset to its default value (which may
		 * be completely unset), otherwise @value becomes the new value.
		 *
		 * If @tag is non-%NULL then it is set to the unique tag associated with this write.  This is the same
		 * tag that appears in change notifications.
		 **/
		public bool write (string key, Variant? value, out string tag = null, Cancellable? cancellable = null) throws Error {
			if (&tag == null) { /* bgo #591673 */
				string junk;
				call_sync (engine.write (key, value), out junk, cancellable);
			} else {
				call_sync (engine.write (key, value), out tag, cancellable);
			}
			return true;
		}

		/**
		 * dconf_client_write_async:
		 * @client: a #DConfClient
		 * @key: a dconf key
		 * @value: (allow-none): a #GVariant, or %NULL
		 * @cancellable: a #GCancellable, or %NULL
		 * @callback: the function to call when complete
		 * @user_data: the user data for @callback
		 *
		 * Writes a value to the given @key, or reset @key to its default value.
		 *
		 * This is the asynchronous version of dconf_client_write().  You should call
		 * dconf_client_write_finish() from @callback to collect the result.
		 **/
		public async bool write_async (string key, Variant? value, out string tag = null, Cancellable? cancellable = null) throws Error {
			yield call_async (engine.write (key, value), out tag, cancellable);
			return true;
		}

		/**
		 * dconf_client_set_locked:
		 * @client: a #DConfClient
		 * @path: a dconf path
		 * @locked: %TRUE to lock, %FALSE to unlock
		 * @cancellable: a #GCancellable, or %NULL
		 * @error: a pointer to a #GError, or %NULL
		 * @returns: %TRUE if setting the lock was successful
		 *
		 * Marks a dconf path as being locked.
		 *
		 * Locks do not affect writes to this #DConfClient.  You can still write to a key that is marked as
		 * being locked without problems.
		 *
		 * Locks are only effective when they are set on a database that is being used as the source of
		 * default/mandatory values.  In that case, the lock will prevent writes from occuring to the database
		 * that has this database as its defaults.
		 **/
		public bool set_locked (string path, bool locked, Cancellable? cancellable = null) throws Error {
			call_sync (engine.set_locked (path, locked), null, cancellable);
			return true;
		}

		/**
		 * dconf_client_set_locked_async:
		 * @client: a #DConfClient
		 * @path: a dconf path
		 * @locked: %TRUE to lock, %FALSE to unlock
		 * @cancellable: a #GCancellable, or %NULL
		 * @callback: the function to call when complete
		 * @user_data: the user data for @callback
		 *
		 * Marks a dconf path as being locked.
		 *
		 * This is the asynchronous version of dconf_client_set_locked().  You should call
		 * dconf_client_write_finish() from @callback to collect the result.
		 **/
		public async bool set_locked_async (string key, bool locked, Cancellable? cancellable = null) throws Error {
			yield call_async (engine.set_locked (key, locked), null, cancellable);
			return true;
		}

		/**
		 * @client: a #DConfClient
		 * @key: a valid dconf key
		 * @returns: the value corresponding to @key, or %NULL if there is none
		 *
		 * Reads the value named by @key from dconf.  If no such value exists, %NULL is returned.
		 */
		public Variant? read (string key) {
			return engine.read (key);
		}

		/**
		 * dconf_client_read_default:
		 * @client: a #DConfClient
		 * @key: a valid dconf key
		 * @returns: the default value corresponding to @key, or %NULL if there is none
		 *
		 * Reads the value named by @key from any existing default/mandatory databases but ignoring any value
		 * set by the user.  The result is as if the named key had just been reset.
		 **/
		public Variant? read_default (string key) {
			return engine.read_default (key);
		}

		/**
		 * dconf_client_read_no_default:
		 * @client: a #DConfClient
		 * @key: a valid dconf key
		 * @returns: the user value corresponding to @key, or %NULL if there is none
		 *
		 * Reads the value named by @key as set by the user, ignoring any default/mandatory databases.  Normal
		 * applications will never want to do this, but it may be useful for administrative or configuration
		 * tweaking utilities to have access to this information.
		 *
		 * Note that in the case of mandatory keys, the result of dconf_client_read_no_default() with a fallback
		 * to dconf_client_read_default() is not necessarily the same as the result of a dconf_client_read().
		 * This is because the user may have set a value before the key became marked as mandatory, in which
		 * case this call will see the user's (otherwise inaccessible) key.
		 **/
		public Variant? read_no_default (string key) {
			return engine.read_no_default (key);
		}

		/**
		 * dconf_client_list:
		 * @client: a #DConfClient
		 * @dir: a dconf dir
		 * @length: the number of items that were returned
		 * @returns: (array length=length): the paths located directly below @dir
		 *
		 * Lists the keys and dirs located directly below @dir.
		 *
		 * You should free the return result with g_strfreev() when it is no longer needed.
		 **/
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
				assert (dcem.bus_type == 'e');
				var connection = Bus.get_sync (BusType.SESSION, null);
				return connection.call_sync (dcem.destination, dcem.object_path, dcem.@interface, dcem.method,
				                             dcem.body, dcem.reply_type, DBusCallFlags.NONE, -1, null);
			} catch {
				return null;
			}
		}

		/**
		 * dconf_client_new:
		 * @profile: the dconf profile to use, or %NULL
		 * @watch_func: the function to call when changes occur
		 * @user_data: the user_data to pass to @watch_func
		 * @notify: the function to free @user_data when no longer needed
		 * @returns: a new #DConfClient
		 *
		 * Creates a new #DConfClient for the given context.
		 *
		 * If @profile is non-%NULL then it specifies the name of the profile to use.  If @profile is %NULL then
		 * the DCONF_PROFILE environment variable is consulted.  If that is unset then the default profile of
		 * "user" is used.  If a profile named "user" is not installed then the dconf client is setup to access
		 * ~/.config/dconf/user.
		 **/
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
