private class KeyValueRenderer: Gtk.CellRenderer
{
    private Gtk.CellRendererText text_renderer;
    private Gtk.CellRendererToggle toggle_renderer;
    private Gtk.CellEditable cell_editor;

    private Key _key;
    public Key key
    {
        get { return _key; }
        set
        {
            _key = value;
            if (_key.value.is_of_type(VariantType.BOOLEAN))
                mode = Gtk.CellRendererMode.ACTIVATABLE;
            else if (_key.value.is_of_type(VariantType.STRING) ||
                     _key.value.is_of_type(VariantType.BYTE) ||
                     _key.value.is_of_type(VariantType.INT16) ||
                     _key.value.is_of_type(VariantType.UINT16) ||
                     _key.value.is_of_type(VariantType.INT32) ||
                     _key.value.is_of_type(VariantType.UINT32) ||
                     _key.value.is_of_type(VariantType.INT64) ||
                     _key.value.is_of_type(VariantType.UINT64) ||
                     _key.value.is_of_type(VariantType.DOUBLE))
                mode = Gtk.CellRendererMode.EDITABLE;
            else
                mode = Gtk.CellRendererMode.INERT;
        }
    }
    
    construct
    {
        text_renderer = new Gtk.CellRendererText();
        toggle_renderer = new Gtk.CellRendererToggle();
        toggle_renderer.xalign = 0f;
    }

    private Gtk.CellRenderer get_renderer()
    {
        if (key.value.is_of_type(VariantType.BOOLEAN))
        {
            toggle_renderer.active = key.value.get_boolean();
            return toggle_renderer;
        }
        else
        {
            text_renderer.text = key.value.print(false);
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
        get_renderer().get_size(widget, cell_area, out x_offset, out y_offset, out width, out height);
    }

    public override void render(Gdk.Window    window,
                                Gtk.Widget    widget,
                                Gdk.Rectangle background_area,
                                Gdk.Rectangle cell_area,
                                Gdk.Rectangle expose_area,
                                Gtk.CellRendererState flags)
    {
        get_renderer().render(window, widget, background_area, cell_area, expose_area, flags);
    }

    public override bool activate(Gdk.Event event,
                                  Gtk.Widget widget,
                                  string path,
                                  Gdk.Rectangle background_area,
                                  Gdk.Rectangle cell_area,
                                  Gtk.CellRendererState flags)
    {
        key.value = new Variant.boolean(!key.value.get_boolean());
        return true;
    }
    
    private void editing_done_cb(Gtk.CellEditable cell_editable)
    {
        cell_editor = null;
        // FIXME: Appears to be broken
        /*if (cell_editable.editing_canceled)
            return;*/

        if (key.value.is_of_type(VariantType.STRING))
        {
            var entry = (Gtk.Entry)cell_editable;
            key.value = new Variant.string(entry.get_text());
            return;
        }

        var spin = (Gtk.SpinButton)cell_editable;
        if (key.value.is_of_type(VariantType.BYTE))
            key.value = new Variant.byte((uchar)spin.get_value_as_int());
        else if (key.value.is_of_type(VariantType.INT16))
            key.value = new Variant.int16((int16)spin.get_value_as_int());
        else if (key.value.is_of_type(VariantType.UINT16))
            key.value = new Variant.uint16((uint16)spin.get_value_as_int());
        else if (key.value.is_of_type(VariantType.INT32))
            key.value = new Variant.int32(spin.get_value_as_int());
        else if (key.value.is_of_type(VariantType.UINT32))
            key.value = new Variant.uint32(spin.get_value_as_int());
        else if (key.value.is_of_type(VariantType.INT64))
            key.value = new Variant.int64(spin.get_value_as_int());
        else if (key.value.is_of_type(VariantType.UINT64))
            key.value = new Variant.uint64(spin.get_value_as_int());
        else if (key.value.is_of_type(VariantType.DOUBLE))
            key.value = new Variant.double(spin.get_value());
    }

    public override unowned Gtk.CellEditable start_editing(Gdk.Event event,
                                                           Gtk.Widget widget,
                                                           string path,
                                                           Gdk.Rectangle background_area,
                                                           Gdk.Rectangle cell_area,
                                                           Gtk.CellRendererState flags)
    {
        if (key.value.is_of_type(VariantType.STRING))
        {
            var entry = new Gtk.Entry();
            entry.set_text(_key.value.get_string());
            cell_editor = entry;
        }
        else if (key.value.is_of_type(VariantType.BYTE))
        {
            var spin = new Gtk.SpinButton.with_range(0, 255, 1);
            spin.set_value(key.value.get_byte());
            cell_editor = spin;
        }
        else if (key.value.is_of_type(VariantType.INT16))
        {
            var spin = new Gtk.SpinButton.with_range(int16.MIN, int16.MAX, 1);
            spin.set_value(key.value.get_int16());
            cell_editor = spin;
        }
        else if (key.value.is_of_type(VariantType.UINT16))
        {
            var spin = new Gtk.SpinButton.with_range(0, uint16.MAX, 1);
            spin.set_value(key.value.get_uint16());
            cell_editor = spin;
        }
        else if (key.value.is_of_type(VariantType.INT32))
        {
            var spin = new Gtk.SpinButton.with_range(int32.MIN, int32.MAX, 1);
            spin.set_value(key.value.get_int32());
            cell_editor = spin;
        }
        else if (key.value.is_of_type(VariantType.UINT32))
        {
            var spin = new Gtk.SpinButton.with_range(0, uint32.MAX, 1);
            spin.set_value(key.value.get_uint32());
            cell_editor = spin;
        }
        else if (key.value.is_of_type(VariantType.INT64))
        {
            var spin = new Gtk.SpinButton.with_range(int64.MIN, int64.MAX, 1);
            spin.set_value(key.value.get_int64());
            cell_editor = spin;
        }
        else if (key.value.is_of_type(VariantType.UINT64))
        {
            var spin = new Gtk.SpinButton.with_range(0, uint64.MAX, 1);
            spin.set_value(key.value.get_uint64());
            cell_editor = spin;
        }
        else if (key.value.is_of_type(VariantType.DOUBLE))
        {
            var spin = new Gtk.SpinButton.with_range(double.MIN, double.MAX, 1);
            spin.set_value(key.value.get_uint64());
            cell_editor = spin;
        }
        cell_editor.editing_done.connect(editing_done_cb);
        cell_editor.show();
        return cell_editor;
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
        insert_column_with_attributes(-1, "Value", new KeyValueRenderer(), "key", 0, null);
    }
}
