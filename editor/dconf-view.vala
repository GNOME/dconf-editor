private class KeyValueRenderer: Gtk.CellRenderer
{
    private DConfKeyView view;
    private Gtk.CellRendererText text_renderer;
    private Gtk.CellRendererSpin spin_renderer;
    private Gtk.CellRendererToggle toggle_renderer;
    private Gtk.CellRendererCombo combo_renderer;

    private Key _key;
    public Key key
    {
        get { return _key; }
        set
        {
            _key = value;
            if (key.type_string == "s")
            {
                text_renderer.text = key.value.get_string();
            }
            else if (key.type_string == "<enum>")
            {
                combo_renderer.text = key.value.get_string();
                combo_renderer.model = new EnumModel(key.schema.schema.list.enums.lookup(key.schema.enum_name));
                mode = Gtk.CellRendererMode.EDITABLE;
            }
            else if (key.type_string == "b")
            {
                toggle_renderer.active = key.value.get_boolean();
                mode = Gtk.CellRendererMode.ACTIVATABLE;
            }
            else if (key.type_string == "s")
            {
                text_renderer.text = key.value.get_string();
                mode = Gtk.CellRendererMode.EDITABLE;
            }
            else if (key.type_string == "y")
            {
                spin_renderer.text = key.value.print(false);
                spin_renderer.adjustment = new Gtk.Adjustment(key.value.get_byte(), 0, 255, 1, 0, 0);
                spin_renderer.digits = 0;
                mode = Gtk.CellRendererMode.EDITABLE;
            }
            else if (key.type_string == "n")
            {
                spin_renderer.text = key.value.print(false);
                spin_renderer.adjustment = new Gtk.Adjustment(key.value.get_int16(), int16.MIN, int16.MAX, 1, 0, 0);
                spin_renderer.digits = 0;
                mode = Gtk.CellRendererMode.EDITABLE;
            }
            else if (key.type_string == "q")
            {
                spin_renderer.text = key.value.print(false);
                spin_renderer.adjustment = new Gtk.Adjustment(key.value.get_uint16(), uint16.MIN, uint16.MAX, 1, 0, 0);
                spin_renderer.digits = 0;
                mode = Gtk.CellRendererMode.EDITABLE;
            }
            else if (key.type_string == "i")
            {
                spin_renderer.text = key.value.print(false);
                spin_renderer.adjustment = new Gtk.Adjustment(key.value.get_int32(), int32.MIN, int32.MAX, 1, 0, 0);
                spin_renderer.digits = 0;
                mode = Gtk.CellRendererMode.EDITABLE;
            }
            else if (key.type_string == "u")
            {
                spin_renderer.text = key.value.print(false);
                spin_renderer.adjustment = new Gtk.Adjustment(key.value.get_uint32(), int32.MIN, uint32.MAX, 1, 0, 0);
                spin_renderer.digits = 0;
                mode = Gtk.CellRendererMode.EDITABLE;
            }
            else if (key.type_string == "x")
            {
                spin_renderer.text = key.value.print(false);
                spin_renderer.adjustment = new Gtk.Adjustment(key.value.get_int64(), int64.MIN, int64.MAX, 1, 0, 0);
                spin_renderer.digits = 0;
                mode = Gtk.CellRendererMode.EDITABLE;
            }
            else if (key.type_string == "t")
            {
                spin_renderer.text = key.value.print(false);
                spin_renderer.adjustment = new Gtk.Adjustment(key.value.get_uint64(), uint64.MIN, uint64.MAX, 1, 0, 0);
                spin_renderer.digits = 0;
                mode = Gtk.CellRendererMode.EDITABLE;
            }
            else if (key.type_string == "d")
            {
                spin_renderer.text = key.value.print(false);
                spin_renderer.adjustment = new Gtk.Adjustment(key.value.get_double(), double.MIN, double.MAX, 1, 0, 0);
                spin_renderer.digits = 6;
                mode = Gtk.CellRendererMode.EDITABLE;
            }
            else
            {
                text_renderer.text = key.value.print(false);            
                mode = Gtk.CellRendererMode.INERT;
            }
        }
    }

    construct
    {
        text_renderer = new Gtk.CellRendererText();
        text_renderer.editable = true;
        text_renderer.edited.connect(text_edited_cb);

        spin_renderer = new Gtk.CellRendererSpin();
        spin_renderer.editable = true;
        spin_renderer.edited.connect(spin_edited_cb);

        toggle_renderer = new Gtk.CellRendererToggle();
        toggle_renderer.xalign = 0f;
        toggle_renderer.activatable = true;
        toggle_renderer.toggled.connect(toggle_cb);

        combo_renderer = new Gtk.CellRendererCombo();
        combo_renderer.has_entry = false;
        combo_renderer.text_column = 0;
        combo_renderer.editable = true;
        combo_renderer.edited.connect(text_edited_cb);
    }

    public KeyValueRenderer(DConfKeyView view)
    {
        this.view = view;
    }

    private Gtk.CellRenderer renderer
    {
        set {}
        get
        {
            if (key.type_string == "<enum>")
                return combo_renderer;
            else if (key.type_string == "b")
                return toggle_renderer;
            else if (key.type_string == "s")
                return text_renderer;
            else if (key.type_string == "y" ||
                     key.type_string == "n" ||
                     key.type_string == "q" ||
                     key.type_string == "i" ||
                     key.type_string == "u" ||
                     key.type_string == "x" ||
                     key.type_string == "t" ||
                     key.type_string == "d")
                return spin_renderer;
            else
                return text_renderer;            
        }
    }

    public override void get_size(Gtk.Widget     widget,
                                  Gdk.Rectangle? cell_area,
                                  out int        x_offset,
                                  out int        y_offset,
                                  out int        width,
                                  out int        height)
    {
        renderer.get_size(widget, cell_area, out x_offset, out y_offset, out width, out height);
    }

    public override void render(Gdk.Window    window,
                                Gtk.Widget    widget,
                                Gdk.Rectangle background_area,
                                Gdk.Rectangle cell_area,
                                Gdk.Rectangle expose_area,
                                Gtk.CellRendererState flags)
    {
        renderer.render(window, widget, background_area, cell_area, expose_area, flags);
    }

    public override bool activate(Gdk.Event event,
                                  Gtk.Widget widget,
                                  string path,
                                  Gdk.Rectangle background_area,
                                  Gdk.Rectangle cell_area,
                                  Gtk.CellRendererState flags)
    {
        return renderer.activate(event, widget, path, background_area, cell_area, flags);
    }

    public override unowned Gtk.CellEditable start_editing(Gdk.Event event,
                                                           Gtk.Widget widget,
                                                           string path,
                                                           Gdk.Rectangle background_area,
                                                           Gdk.Rectangle cell_area,
                                                           Gtk.CellRendererState flags)
    {
        return renderer.start_editing(event, widget, path, background_area, cell_area, flags);
    }
    
    private Key get_key_from_path(string path)
    {
        Gtk.TreeIter iter;
        view.model.get_iter_from_string(out iter, path);

        Key key;
        view.model.get(iter, 0, out key, -1);
        
        return key;
    }

    private void toggle_cb(Gtk.CellRendererToggle renderer, string path)
    {
        Key key = get_key_from_path(path);
        key.value = new Variant.boolean(!key.value.get_boolean());
    }

    private void text_edited_cb(Gtk.CellRendererText renderer, string path, string text)
    {
        Key key = get_key_from_path(path);
        key.value = new Variant.string(text);
    }

    private void spin_edited_cb(Gtk.CellRendererText renderer, string path, string text)
    {
        Key key = get_key_from_path(path);
        if (key.type_string == "y")
            key.value = new Variant.byte((uchar)text.to_int());
        else if (key.type_string == "n")
            key.value = new Variant.int16((int16)text.to_int());
        else if (key.type_string == "q")
            key.value = new Variant.uint16((uint16)text.to_int());
        else if (key.type_string == "i")
            key.value = new Variant.int32(text.to_int());
        else if (key.type_string == "u")
            key.value = new Variant.uint32(text.to_int());
        else if (key.type_string == "x")
            key.value = new Variant.int64(text.to_int());
        else if (key.type_string == "t")
            key.value = new Variant.uint64(text.to_int());
        else if (key.type_string == "d")
            key.value = new Variant.double(text.to_double());
    }
}

public class DConfDirView : Gtk.TreeView
{
    public DConfDirView()
    {
        set_headers_visible(false);
        insert_column_with_attributes(-1, "Key", new Gtk.CellRendererText(), "text", 1, null);
    }
}

public class DConfKeyView : Gtk.TreeView
{
    public DConfKeyView()
    {
        var column = new Gtk.TreeViewColumn.with_attributes("Name", new Gtk.CellRendererText(), "text", 1, "weight", 4, null);
        /*column.set_sort_column_id(1);*/
        append_column(column);
        insert_column_with_attributes(-1, "Value", new KeyValueRenderer(this), "key", 0, null);
    }
}
