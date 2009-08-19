using Gtk;

namespace Editor {
  class EditorWindow : Window {
    override void constructed () {
      var hp = new HPaned ();
      add (hp);

      var model = new Model ();
      var keys = new KeysView (model);
      var paths = new PathsView (model, keys);

      hp.add1 (paths);
      hp.add2 (keys);

      hp.set_position (160);
      hp.show_all ();
    }
  }

  class PathsView : TreeView {
    KeysView keys_view;
    PathsFilter filter;

    override void constructed () {
      var renderer = new CellRendererText ();
      insert_column_with_attributes (0, "name", renderer, "text", 0);
    }

    public PathsView (Model model, KeysView keys_view) {
      this.filter = new PathsFilter (model);
      this.model = filter;
      this.keys_view = keys_view;
    }

    override void cursor_changed () {
      TreePath path;

      get_cursor (out path, null);
      path = filter.convert_path_to_child_path (path);

      keys_view.show_path (path);
    }
  }

  class ValueRenderer : CellRendererText {
    string _key;

    public string key {
      set {
        _key = value;
        var _value = dconf.get (_key);

        if (_value != null)
          text = _value.print (true);
        else
          text = "<none>";
      }
    }

    override void constructed () {
      editable = true;
    }

    override void edited (string path, string text) {
      // XXX using _key might be wrong...
      // XXX is the most recently rendered thing the one?
      print ("  %s <= '%s'\n", _key, text);
      dconf.set (_key, new Variant.string (text));
    }
  }

  class KeysView : TreeView {
    public Model base_model { get; construct; }

    override void constructed () {
      var renderer = new CellRendererText ();
      insert_column_with_attributes (0, "name", renderer, "text", 0);

      renderer = new ValueRenderer ();
      insert_column_with_attributes (1, "name", renderer, "key", 1);
    }

    public void show_path (TreePath path) {
      this.model = new KeysFilter (base_model, path);
    }

    public KeysView (Model base_model) {
      this.base_model = base_model;
    }
  }

  class PathsFilter : TreeModelFilter {
    override void constructed () {
      set_visible_func (visible_func);
    }

    bool visible_func (TreeModel child, TreeIter iter) {
      string ?path;

      child.get (iter, 0, out path);
      return path != null && path.has_suffix ("/");
    }

    public PathsFilter (Model child_model) {
      this.child_model = child_model;
    }
  }

  class KeysFilter : TreeModelFilter {
    override void constructed () {
      set_visible_func (visible_func);
    }

    bool visible_func (TreeModel child, TreeIter iter) {
      string path;

      child.get (iter, 0, out path);
      return path != null && !path.has_suffix ("/");
    }

    public KeysFilter (Model child_model, TreePath path) {
      this.child_model = child_model;
      this.virtual_root = path;
    }
  }

  class Model : TreeStore {
    override void constructed () {
      TreeIter root;
      set_column_types (new GLib.Type [] { typeof (string),
                                           typeof (string) });

      dconf.watch ("/", change);

      insert (out root, null, 0);
      set (root, 0, "/");
      set (root, 1, "/");
      introduce_path ("/", root);
    }

    void change (string key) {
      var value = dconf.get (key);

      change_value ("", key, null, value);
    }

    void change_value (string path, string key, TreeIter ?iter, Variant ?value) {
      bool is_dir = false;
      TreeIter child;
      int i, n;

      for (i = 0; key[i] != '\0' && key[i] != '/'; i++);

      if (key[i] == '/') {
        is_dir = true;
        i++;
      }

      var rel = key.ndup (i);

      var valid = iter_children (out child, iter);

      for (n = 0; valid; n++) {
        weak string name;

        get (child, 0, out name);

        if (name > rel)
          valid = false;

        if (name >= rel)
          break;

        valid = iter_next (ref child);
      }

      if (!valid)
        {
          insert (out child, iter, n);
          set (child, 0, rel);
          set (child, 1, path + rel);
        }

      if (is_dir) {
        change_value (path + rel, key.substring (i), child, value);
      } else if (valid) {
        row_changed (get_path (child), child);
      }
    }

    void introduce_path (string path, TreeIter ?parent) {
      foreach (var item in dconf.list (path)) {
        TreeIter iter;

        append (out iter, parent);
        set (iter, 0, item);
        set (iter, 1, path + item);

        if (item.has_suffix ("/")) {
          introduce_path (path + item, iter);
        }
      }
    }
  }

  void main (string [] args) {
    Gtk.init (ref args);

    var window = new EditorWindow ();
    window.set_default_size (500, 200);
    window.show ();

    Gtk.main ();
  }
}
