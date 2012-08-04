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
            
            if (key.has_schema && key.schema.choices != null)
            {
                combo_renderer.text = key.value.print(false);
                var model = new Gtk.ListStore(2, typeof(string), typeof(string));
                foreach (var choice in key.schema.choices)
                {
                    Gtk.TreeIter iter;
                    model.append(out iter);
                    model.set(iter, 0, choice.name, 1, choice.value.print(false), -1);
                }
                combo_renderer.model = model;
                mode = Gtk.CellRendererMode.EDITABLE;
                return;
            }

            switch (key.type_string)
            {
            case "<enum>":
                combo_renderer.text = key.value.get_string();
                combo_renderer.model = new EnumModel(key.schema.schema.list.enums.lookup(key.schema.enum_name));
                mode = Gtk.CellRendererMode.EDITABLE;
                break;
            case "b":
                toggle_renderer.active = key.value.get_boolean();
                mode = Gtk.CellRendererMode.ACTIVATABLE;
                break;
            case "s":
                text_renderer.text = key.value.get_string();
                mode = Gtk.CellRendererMode.EDITABLE;
                break;
            case "y":
            case "n":
            case "q":
            case "i":
            case "u":
            case "x":
            case "t":
            case "d":
                spin_renderer.text = key.value.print(false);
                var v = get_variant_as_double(key.value);
                double min = 0.0, max = 0.0;
                if (key.has_schema && key.schema.range != null)
                {
                    min = get_variant_as_double(key.schema.range.min);
                    max = get_variant_as_double(key.schema.range.max);
                }
                else
                {
                    min = get_variant_as_double(key.get_min());
                    max = get_variant_as_double(key.get_max());
                }
                spin_renderer.adjustment = new Gtk.Adjustment(v, min, max, 1, 0, 0);
                spin_renderer.digits = 0;
                mode = Gtk.CellRendererMode.EDITABLE;
                break;
            default:
                text_renderer.text = key.value.print(false);            
                mode = Gtk.CellRendererMode.EDITABLE;
                break;
            }
        }
    }

    private static double get_variant_as_double(Variant value)
    {
        if (value == null)
            return 0.0;

        switch (value.classify ())
        {
        case Variant.Class.BYTE:
            return (double)value.get_byte();
        case Variant.Class.INT16:
            return (double)value.get_int16();
        case Variant.Class.UINT16:
            return (double)value.get_uint16();
        case Variant.Class.INT32:
            return (double)value.get_int32();
        case Variant.Class.UINT32:
            return (double)value.get_uint32();
        case Variant.Class.INT64:
            return (double)value.get_int64();
        case Variant.Class.UINT64:
            return (double)value.get_uint64();
        case Variant.Class.DOUBLE:
            return value.get_double();
        default:
            return 0.0;
        }
    }

    public KeyValueRenderer(DConfKeyView view)
    {
        this.view = view;

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

    private Gtk.CellRenderer renderer
    {
        set {}
        get
        {
            if (key.has_schema && key.schema.choices != null)
                return combo_renderer;

            switch (key.type_string)
            {
            case "<enum>":
                return combo_renderer;
            case "b":
                return toggle_renderer;
            case "y":
            case "n":
            case "q":
            case "i":
            case "u":
            case "x":
            case "t":
            case "d":
                return spin_renderer;
            default:
            case "s":
                return text_renderer;
            }
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

    public override void get_preferred_width(Gtk.Widget widget,
                                             out int    minimum_size,
                                             out int    natural_size)
    {
        renderer.get_preferred_width(widget, out minimum_size, out natural_size);
    }

    public override void get_preferred_height_for_width(Gtk.Widget widget,
                                                        int        width,
                                                        out int    minimum_height,
                                                        out int    natural_height)
    {
        renderer.get_preferred_height_for_width(widget, width, out minimum_height, out natural_height);
    }

    public override void get_preferred_height(Gtk.Widget widget,
                                              out int    minimum_size,
                                              out int    natural_size)
    {
        renderer.get_preferred_height(widget, out minimum_size, out natural_size);
    }

    public override void get_preferred_width_for_height(Gtk.Widget widget,
                                                        int        height,
                                                        out int    minimum_width,
                                                        out int    natural_width)
    {
        renderer.get_preferred_width_for_height(widget, height, out minimum_width, out natural_width);
    }

    public override void render(Cairo.Context context,
                                Gtk.Widget    widget,
                                Gdk.Rectangle background_area,
                                Gdk.Rectangle cell_area,
                                Gtk.CellRendererState flags)
    {
        renderer.render(context, widget, background_area, cell_area, flags);
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
        var key = get_key_from_path(path);
        key.value = new Variant.boolean(!key.value.get_boolean());
    }

    private void text_edited_cb(Gtk.CellRendererText renderer, string path, string text)
    {
        var key = get_key_from_path(path);
        if (key.type_string == "s" || key.type_string == "<enum>")
        {
            key.value = new Variant.string(text);
        }
        else
        {
            try
            {
                var value = Variant.parse(new VariantType(key.type_string), text);
                key.value = value;
            }
            catch (VariantParseError e)
            {
                var dialog = new Gtk.MessageDialog(null, Gtk.DialogFlags.MODAL, Gtk.MessageType.WARNING, Gtk.ButtonsType.OK, _("Error setting value: %s"), e.message);
                dialog.run();
                dialog.destroy();
            }
        }
    }

    private void spin_edited_cb(Gtk.CellRendererText renderer, string path, string text)
    {
        Key key = get_key_from_path(path);
        switch (key.type_string)
        {
        case "y":
            key.value = new Variant.byte((uchar)int.parse(text));
            break;
        case "n":
            key.value = new Variant.int16((int16)int.parse(text));
            break;
        case "q":
            key.value = new Variant.uint16((uint16)int.parse(text));
            break;
        case "i":
            key.value = new Variant.int32(int.parse(text));
            break;
        case "u":
            key.value = new Variant.uint32(int.parse(text));
            break;
        case "x":
            key.value = new Variant.int64(int.parse(text));
            break;
        case "t":
            key.value = new Variant.uint64(int.parse(text));
            break;
        case "d":
            key.value = new Variant.double(double.parse(text));
            break;
        }
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
		/* Translators: this is the column header label in the main view */
        var column = new Gtk.TreeViewColumn.with_attributes(_("Name"), new Gtk.CellRendererText(), "text", 1, "weight", 4, null);
        /*column.set_sort_column_id(1);*/
        append_column(column);
		/* Translators: this is the column header label in the main view */
        insert_column_with_attributes(-1, _("Value"), new KeyValueRenderer(this), "key", 0, null);
    }
}
