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
    public int32 get_int32 ();

    public GLib.StringBuilder markup_print (GLib.StringBuilder ?string = null,
                                bool newline = false,
                                int indentation = 0,
                                int tabstop = 0);
  }
}

[CCode (cheader_filename = "dconf/dconf.h")]

namespace dconf {
  delegate void WatchFunc (string key, string[] items, uint32 sequence);

  GLib.Variant? get (string key);
  string[] list (string path);
  bool get_locked (string path);
  bool get_writable (string path);

  void set (string key, GLib.Variant value,
            out uint32 sequence = null) throws GLib.Error;

  void watch (string path, WatchFunc callback);
  void unwatch (string path, WatchFunc callback);
}
