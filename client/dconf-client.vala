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

			if (dcem.bus_types[0] == 'e') {
				if (session == null) {
					session = Bus.get_sync (BusType.SESSION, cancellable);
				}
				connection = session;
			} else {
				assert (dcem.bus_types[0] == 'y');
				if (system == null) {
					system = Bus.get_sync (BusType.SYSTEM, cancellable);
				}
				connection = system;
			}

			foreach (var message in dcem.parameters) {
				var reply = connection.call_sync (dcem.bus_name, dcem.object_path, dcem.interface_name, dcem.method_name,
				                                  message, dcem.reply_type, DBusCallFlags.NONE, -1, cancellable);
				if (!dcem.reply_type.equal (VariantType.UNIT)) {
					reply.get ("(s)", out tag);
				}
			}
		}

		async void call_async (EngineMessage dcem, out string tag, Cancellable? cancellable) throws Error {
			DBusConnection connection;

			if (dcem.bus_types[0] == 'e') {
				if (session == null) {
					session = yield Bus.get (BusType.SESSION, cancellable);
				}
				connection = session;
			} else {
				assert (dcem.bus_types[0] == 'y');
				if (system == null) {
					system = yield Bus.get (BusType.SYSTEM, cancellable);
				}
				connection = system;
			}

			foreach (var message in dcem.parameters) {
				var reply = yield connection.call (dcem.bus_name, dcem.object_path, dcem.interface_name, dcem.method_name,
				                                   message, dcem.reply_type, DBusCallFlags.NONE, -1, cancellable);
				if (dcem.reply_type != VariantType.UNIT) {
					reply.get ("(s)", out tag);
				}
			}
		}

		/**
		 * dconf_client_is_writable:
		 * @client: a #DConfClient
		 * @key: a dconf key
		 * Returns: %TRUE is @key is writable
		 *
		 * Checks if @key is writable (ie: the key has no mandatory setting).
		 *
		 * This call does not verify that writing to the key will actually be successful.  It only checks for
		 * the existence of mandatory keys/locks that might affect writing to @key.  Other issues (such as a
		 * full disk or an inability to connect to the bus and start the service) may cause the write to fail.
		 **/
		public bool is_writable (string key) {
			return engine.is_writable (key);
		}

		/**
		 * dconf_client_write:
		 * @client: a #DConfClient
		 * @key: a dconf key
		 * @value: (allow-none): a #GVariant, or %NULL
		 * @tag: (out) (allow-none): the tag from this write
		 * @cancellable: a #GCancellable, or %NULL
		 * @error: a pointer to a #GError, or %NULL
		 * Returns: %TRUE if the write is successful
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
		 * Write a value to the given @key, or reset @key to its default value.
		 *
		 * This is the asynchronous version of dconf_client_write().  You should call
		 * dconf_client_write_finish() from @callback to collect the result.
		 **/
		public async bool write_async (string key, Variant? value, out string tag = null, Cancellable? cancellable = null) throws Error {
			yield call_async (engine.write (key, value), out tag, cancellable);
			return true;
		}

		/**
		 * dconf_client_write_many:
		 * @client: a #DConfClient
		 * @dir: the dconf directory under which to make the writes
		 * @rels: a %NULL-terminated array of relative keys
		 * @values: an array of possibly-%NULL #GVariant pointers
		 * @n_values: the length of @values, which must be equal to the length of @rels
		 * @tag: (out) (allow-none): the tag from this write
		 * @cancellable: a #GCancellable, or %NULL
		 * @error: a pointer to a #GError, or %NULL
		 * Returns: %TRUE if the write is successful
		 *
		 * Write multiple values at once.
		 *
		 * For each pair of items from @rels and @values, the value is written to the result of concatenating
		 * @dir with the relative path.  As with dconf_client_write(), if a given value is %NULL then the effect
		 * is that the specified key is reset.
		 *
		 * If @tag is non-%NULL then it is set to the unique tag associated with this write.  This is the same
		 * tag that appears in change notifications.
		 **/
		public bool write_many (string dir, [CCode (array_length = false, array_null_terminated = true)] string[] rels, Variant?[] values, out string? tag = null, Cancellable? cancellable = null) throws Error {
			if (&tag == null) { /* bgo #591673 */
				string junk;
				call_sync (engine.write_many (dir, rels, values), out junk, cancellable);
			} else {
				call_sync (engine.write_many (dir, rels, values), out tag, cancellable);
			}
			return true;
		}

		/*< disabled due to Vala compiler bugs >
		 * dconf_client_write_many_async:
		 * @client: a #DConfClient
		 * @dir: the dconf directory under which to make the writes
		 * @rels: a %NULL-terminated array of relative keys
		 * @values: an array of possibly-%NULL #GVariant pointers
		 * @n_values: the length of @values, which must be equal to the length of @rels
		 * @cancellable: a #GCancellable, or %NULL
		 * @callback: a #GAsyncReadyCallback to call when finished
		 * @user_data: a pointer to pass as the last argument to @callback
		 *
		 * Write multiple values at once.
		 *
		 * This is the asynchronous version of dconf_client_write_many().  You should call
		 * dconf_client_write_many_finish() from @callback to collect the result.
		 *
			public async bool write_many_async (string dir, [CCode (array_length = false, array_null_terminated = true)] string[] rels, Variant?[] values, out string? tag = null, Cancellable? cancellable = null) throws Error {
			yield call_async (engine.write_many (dir, rels, values), out tag, cancellable);
			return true;
		}*/

		/**
		 * dconf_client_set_locked:
		 * @client: a #DConfClient
		 * @path: a dconf path
		 * @locked: %TRUE to lock, %FALSE to unlock
		 * @cancellable: a #GCancellable, or %NULL
		 * @error: a pointer to a #GError, or %NULL
		 * Returns: %TRUE if setting the lock was successful
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
		 * dconf_client_set_locked_finish() from @callback to collect the result.
		 **/
		public async bool set_locked_async (string key, bool locked, Cancellable? cancellable = null) throws Error {
			yield call_async (engine.set_locked (key, locked), null, cancellable);
			return true;
		}

		/**
		 * dconf_client_read:
		 * @client: a #DConfClient
		 * @key: a valid dconf key
		 * Returns: the value corresponding to @key, or %NULL if there is none
		 *
		 * Reads the value named by @key from dconf.  If no such value exists, %NULL is returned.
		 **/
		public Variant? read (string key) {
			return engine.read (key);
		}

		/**
		 * dconf_client_read_default:
		 * @client: a #DConfClient
		 * @key: a valid dconf key
		 * Returns: the default value corresponding to @key, or %NULL if there is none
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
		 * Returns: the user value corresponding to @key, or %NULL if there is none
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
		 * Returns: (array length=length): the paths located directly below @dir
		 *
		 * Lists the keys and dirs located directly below @dir.
		 *
		 * You should free the return result with g_strfreev() when it is no longer needed.
		 **/
		public string[] list (string dir) {
			return engine.list (dir);
		}

		/**
		 * dconf_client_watch:
		 * @client: a #DConfClient
		 * @path: a dconf path
		 * @cancellable: a #GCancellable, or %NULL
		 * @error: a pointer to a %NULL #GError, or %NULL
		 * Returns: %TRUE on success, else %FALSE with @error set
		 *
		 * Requests monitoring of a portion of the dconf database.
		 *
		 * If @path is a key (ie: doesn't end with a slash) then a single key is monitored for changes.  If
		 * @path is a dir (ie: sending with a slash) then all keys that have @path as a prefix are monitored.
		 *
		 * This function blocks until the watch has definitely been established with the bus daemon.  If you
		 * would like a non-blocking version of this call, see dconf_client_watch_async().
		 **/
		public bool watch (string path, Cancellable? cancellable = null) throws GLib.Error {
			call_sync (engine.watch (path), null, cancellable);
			return true;
		}

		/**
		 * dconf_client_watch_async:
		 * @client: a #DConfClient
		 * @path: a dconf path
		 * @cancellable: a #GCancellable, or %NULL
		 * @callback: a #GAsyncReadyCallback to call when finished
		 * @user_data: a pointer to pass as the last argument to @callback
		 *
		 * Requests monitoring of a portion of the dconf database.
		 *
		 * This is the asynchronous version of dconf_client_watch().  You should call
		 * dconf_client_watch_finish() from @callback to collect the result.
		 **/
		public async bool watch_async (string name, Cancellable? cancellable = null) throws GLib.Error {
			yield call_async (engine.watch (name), null, cancellable);
			return true;
		}

		/**
		 * dconf_client_unwatch:
		 * @client: a #DConfClient
		 * @path: a dconf path
		 * @cancellable: a #GCancellable, or %NULL
		 * @error: a pointer to a %NULL #GError, or %NULL
		 * Returns: %TRUE on success, else %FALSE with @error set
		 *
		 * Cancels the effect of a previous call to dconf_client_watch().
		 *
		 * If the same path has been watched multiple times then only one of the watches is cancelled and the
		 * net effect is that the path is still watched.
		 *
		 * This function blocks until the watch has definitely been removed from the bus daemon.  It is possible
		 * that notifications in transit will arrive after this call returns.  For an asynchronous version of
		 * this call, see dconf_client_unwatch_async().
		 **/
		public bool unwatch (string name, Cancellable? cancellable = null) throws GLib.Error {
			call_sync (engine.unwatch (name), null, cancellable);
			return true;
		}

		/**
		 * dconf_client_unwatch_async:
		 * @client: a #DConfClient
		 * @path: a dconf path
		 * @cancellable: a #GCancellable, or %NULL
		 * @callback: a #GAsyncReadyCallback to call when finished
		 * @user_data: a pointer to pass as the last argument to @callback
		 *
		 * Cancels the effect of a previous call to dconf_client_watch().
		 *
		 * This is the asynchronous version of dconf_client_unwatch().  You should call
		 * dconf_client_unwatch_finish() from @callback to collect the result.  No additional notifications will
		 * be delivered for this watch after @callback is called.
		 **/
		public async bool unwatch_async (string name, Cancellable? cancellable = null) throws GLib.Error {
			yield call_async (engine.unwatch (name), null, cancellable);
			return true;
		}

		static Variant? service_func (EngineMessage dcem) {
			try {
				assert (dcem.bus_types[0] == 'e');
				var connection = Bus.get_sync (BusType.SESSION, null);
				return connection.call_sync (dcem.bus_name, dcem.object_path, dcem.interface_name, dcem.method_name,
				                             dcem.parameters[0], dcem.reply_type, DBusCallFlags.NONE, -1, null);
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
		 * Returns: a new #DConfClient
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
