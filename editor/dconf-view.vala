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
            if (key.schema != null && key.value.is_of_type(VariantType.STRING) && key.schema.type == "enum")
            {
                combo_renderer.text = key.value.get_string();
                combo_renderer.model = new EnumModel(key.schema.schema.list.enums[key.schema.enum_name]);
                mode = Gtk.CellRendererMode.EDITABLE;
            }
            else if (key.value.is_of_type(VariantType.BOOLEAN))
            {
                toggle_renderer.active = key.value.get_boolean();
                mode = Gtk.CellRendererMode.ACTIVATABLE;
            }
            else if (key.value.is_of_type(VariantType.STRING))
            {
                text_renderer.text = key.value.get_string();
                mode = Gtk.CellRendererMode.EDITABLE;
            }
            else if (key.value.is_of_type(VariantType.BYTE))
            {
                spin_renderer.text = key.value.print(false);
                spin_renderer.adjustment = new Gtk.Adjustment(key.value.get_byte(), 0, 255, 1, 0, 0);
                spin_renderer.digits = 0;
                mode = Gtk.CellRendererMode.EDITABLE;
            }
            else if (key.value.is_of_type(VariantType.INT16))
            {
                spin_renderer.text = key.value.print(false);
                spin_renderer.adjustment = new Gtk.Adjustment(key.value.get_int16(), int16.MIN, int16.MAX, 1, 0, 0);
                spin_renderer.digits = 0;
                mode = Gtk.CellRendererMode.EDITABLE;
            }
            else if (key.value.is_of_type(VariantType.UINT16))
            {
                spin_renderer.text = key.value.print(false);
                spin_renderer.adjustment = new Gtk.Adjustment(key.value.get_uint16(), uint16.MIN, uint16.MAX, 1, 0, 0);
                spin_renderer.digits = 0;
                mode = Gtk.CellRendererMode.EDITABLE;
            }
            else if (key.value.is_of_type(VariantType.INT32))
            {
                spin_renderer.text = key.value.print(false);
                spin_renderer.adjustment = new Gtk.Adjustment(key.value.get_int32(), int32.MIN, int32.MAX, 1, 0, 0);
                spin_renderer.digits = 0;
                mode = Gtk.CellRendererMode.EDITABLE;
            }
            else if (key.value.is_of_type(VariantType.UINT32))
            {
                spin_renderer.text = key.value.print(false);
                spin_renderer.adjustment = new Gtk.Adjustment(key.value.get_uint32(), int32.MIN, uint32.MAX, 1, 0, 0);
                spin_renderer.digits = 0;
                mode = Gtk.CellRendererMode.EDITABLE;
            }
            else if (key.value.is_of_type(VariantType.INT64))
            {
                spin_renderer.text = key.value.print(false);
                spin_renderer.adjustment = new Gtk.Adjustment(key.value.get_int64(), int64.MIN, int64.MAX, 1, 0, 0);
                spin_renderer.digits = 0;
                mode = Gtk.CellRendererMode.EDITABLE;
            }
            else if (key.value.is_of_type(VariantType.UINT64))
            {
                spin_renderer.text = key.value.print(false);
                spin_renderer.adjustment = new Gtk.Adjustment(key.value.get_uint64(), uint64.MIN, uint64.MAX, 1, 0, 0);
                spin_renderer.digits = 0;
                mode = Gtk.CellRendererMode.EDITABLE;
            }
            else if (key.value.is_of_type(VariantType.DOUBLE))
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
            if (key.schema != null && key.schema.type == "enum")
                return combo_renderer;
            else if (key.value.is_of_type(VariantType.BOOLEAN))
                return toggle_renderer;
            else if (key.value.is_of_type(VariantType.STRING))
                return text_renderer;
            else if (key.value.is_of_type(VariantType.BYTE) ||
                     key.value.is_of_type(VariantType.INT16) ||
                     key.value.is_of_type(VariantType.UINT16) ||
                     key.value.is_of_type(VariantType.INT32) ||
                     key.value.is_of_type(VariantType.UINT32) ||
                     key.value.is_of_type(VariantType.INT64) ||
                     key.value.is_of_type(VariantType.UINT64) ||
                     key.value.is_of_type(VariantType.DOUBLE))
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
        if (key.value.is_of_type(VariantType.BYTE))
            key.value = new Variant.byte((uchar)text.to_int());
        else if (key.value.is_of_type(VariantType.INT16))
            key.value = new Variant.int16((int16)text.to_int());
        else if (key.value.is_of_type(VariantType.UINT16))
            key.value = new Variant.uint16((uint16)text.to_int());
        else if (key.value.is_of_type(VariantType.INT32))
            key.value = new Variant.int32(text.to_int());
        else if (key.value.is_of_type(VariantType.UINT32))
            key.value = new Variant.uint32(text.to_int());
        else if (key.value.is_of_type(VariantType.INT64))
            key.value = new Variant.int64(text.to_int());
        else if (key.value.is_of_type(VariantType.UINT64))
            key.value = new Variant.uint64(text.to_int());
        else if (key.value.is_of_type(VariantType.DOUBLE))
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
        var column = new Gtk.TreeViewColumn.with_attributes("Name", new Gtk.CellRendererText(), "text", 1, null);
        /*column.set_sort_column_id(1);*/
        append_column(column);
        insert_column_with_attributes(-1, "Value", new KeyValueRenderer(this), "key", 0, null);
    }
}
