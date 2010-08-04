/* extra docs here until we can emit them with Vala */

/**
 * SECTION:client
 * @title: DConfClient
 * @short_description: Direct read and write access to DConf, based on GDBus
 *
 * This is a simple class that allows an application to directly read
 * from and write to the dconf database.  There is also a very simple
 * mechanism for requesting and receiving notification of changes but
 * not robust mechanism for dispatching change notifications to multiple
 * listeners.
 *
 * Most applications probably don't want to access dconf directly and
 * would be better off using something like #GSettings.
 **/

/**
 * DConfWatchFunc:
 * @client: the #DConfClient emitting the notification
 * @path: the path at which the change occured
 * @items: the items that were changed, given as relative paths
 * @n_items: the length of @items
 * @tag: the tag associated with the change
 * @user_data: the user data given to dconf_client_new()
 *
 * This is the type of the callback given to dconf_client_new().
 *
 * This function is called in response to changes occuring to the dconf
 * database that @client is associated with.
 *
 * @path can either be a key or a dir.  If @path is a key then @items
 * will be empty and the notification should be taken to mean that one
 * key -- the key named by @path -- may have changed.
 *
 * If @path is a dir and @items is empty then it is an indication that
 * any key under @path may have changed.
 *
 * Otherwise (if @items is non-empty) then the set of affected keys is
 * the same as if the watch function had been called multiple times for
 * each item in the array appended to @path.  This includes the
 * possibility of the resulting path being a dir.
 **/

/**
 * DConfClient:
 *
 * An opaque structure type.  May only be used with the following
 * functions.
 **/

/**
 * dconf_client_write_finish:
 * @client: a #DConfClient
 * @result: the #GAsyncResult passed to the #GAsyncReadyCallback
 * @tag: (out) (allow-none): the tag from this write
 * @error: a pointer to a #GError, or %NULL
 *
 * Collects the result from a prior call to dconf_client_write_async().
 **/

/**
 * dconf_client_set_locked_finish:
 * @client: a #DConfClient
 * @result: the #GAsyncResult passed to the #GAsyncReadyCallback
 * @error: a pointer to a #GError, or %NULL
 *
 * Collects the result from a prior call to
 * dconf_client_set_locked_async().
 **/

/**
 * dconf_client_watch_finish:
 * @client: a #DConfClient
 * @result: the #GAsyncResult passed to the #GAsyncReadyCallback
 * @error: a pointer to a #GError, or %NULL
 *
 * Collects the result from a prior call to dconf_client_watch_async().
 **/

/**
 * dconf_client_unwatch_finish:
 * @client: a #DConfClient
 * @result: the #GAsyncResult passed to the #GAsyncReadyCallback
 * @error: a pointer to a #GError, or %NULL
 *
 * Collects the result from a prior call to
 * dconf_client_unwatch_async().
 **/
