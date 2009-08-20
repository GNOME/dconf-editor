namespace GLib {
  [CCode (ref_function = "g_variant_ref",
          unref_function = "g_variant_unref",
          ref_sink_function = "g_variant_ref_sink",
          cheader_filename = "glib/gvariant.h")]
  public class Variant {
    public Variant.int32 (int32 value);
    public Variant.uint32 (uint32 value);
    public Variant.string (string value);

    public weak string get_string (out size_t length = null);
    public string print (bool add_type);
    public int32 get_int32 ();

    public GLib.StringBuilder markup_print (GLib.StringBuilder ?string = null,
                                bool newline = false,
                                int indentation = 0,
                                int tabstop = 0);
  }
}

[CCode (cheader_filename = "dconf.h")]

namespace DConf {
  public struct AsyncResult {
  }

  public delegate void AsyncReadyCallback (AsyncResult result);

  bool is_key (string key);
  bool is_path (string path);
  bool match (string left, string right);

  GLib.Variant? get (string key);
  string[] list (string path);
  bool get_writable (string path);
  bool get_locked (string path);

  void set (string key, GLib.Variant value, out string event_id = null) throws GLib.Error;
  void set_async (string key, GLib.Variant value, DConf.AsyncReadyCallback callback);
  void set_finish (DConf.AsyncResult result, out string event_id = null) throws GLib.Error;

  void set_locked (string key, bool value) throws GLib.Error;
  void set_locked_async (string key, bool value, DConf.AsyncReadyCallback callback);
  void set_locked_finish (DConf.AsyncResult result) throws GLib.Error;

  void reset (string key, out string event_id = null) throws GLib.Error;
  void reset_async (string key, DConf.AsyncReadyCallback callback);
  void reset_finish (DConf.AsyncResult result, out string event_id = null) throws GLib.Error;

  void merge (string prefix, GLib.Tree tree, out string event_id = null) throws GLib.Error;
  void merge_async (string prefix, GLib.Tree tree, DConf.AsyncReadyCallback callback);
  void merge_finish (DConf.AsyncResult result, out string event_id = null) throws GLib.Error;

  delegate void WatchFunc (string prefix, string[] items, string event_id);
  void watch (string path, WatchFunc callback);
  void unwatch (string path, WatchFunc callback);
}
