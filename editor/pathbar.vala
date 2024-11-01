/* Baobab - disk usage analyzer
 *
 * Copyright (C) 2020 Stefano Facchini <stefano.facchini@gmail.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

public class PathButton : Gtk.Button {
    const int DEFAULT_MIN_CHARS = 3;
    // We want to avoid ellipsizing the current directory name, but still need
    // to set a limit.
    const int CURRENT_DIR_MIN_CHARS = DEFAULT_MIN_CHARS * 4;

    private int min_chars { get; set; default = DEFAULT_MIN_CHARS; }
    public bool is_current_dir { get; set; default = false; }

    public PathButton () {
        bind_property ("label", this, "tooltip-text", BindingFlags.SYNC_CREATE);

        notify["child"].connect (on_is_current_dir_changed);
        notify["is-current-dir"].connect (on_is_current_dir_changed);
        notify["label"].connect (on_label_changed);
        notify["min-chars"].connect (on_label_changed);
    }

    private void on_is_current_dir_changed () {
        if (is_current_dir) {
            add_css_class ("current-dir");
            child.remove_css_class ("dim-label");
            child.halign = Gtk.Align.START;
            hexpand = true;
            min_chars = CURRENT_DIR_MIN_CHARS;
        } else {
            remove_css_class ("current-dir");
            child.add_css_class ("dim-label");
            child.halign = Gtk.Align.FILL;
            hexpand = false;
            min_chars = DEFAULT_MIN_CHARS;
        }
    }

    private void on_label_changed () {
        // We'll bend the button's existing GtkLabel to our wishes, instead of
        // creating our own as a child. This is a bit dumb, but the alternative
        // is we need to deal with a behaviour where setting the icon name
        // property replaces our child widget with an image widget. Personally
        // I think this is slightly less bad.

        Gtk.Label? label_widget = child as Gtk.Label;

        if (label_widget == null)
            return;

        // Labels can ellipsize until they become a single ellipsis character.
        // We don't want that, so we must set a minimum.
        //
        // However, for labels shorter than the minimum, setting this minimum
        // width would make them unnecessarily wide. In that case, just make it
        // not ellipsize instead.
        //
        // Due to variable width fonts, labels can be shorter than the space
        // that would be reserved by setting a minimum amount of characters.
        // Compensate for this with a tolerance of +50% characters.
        int label_length = (label != null) ? ((!) label).length : 0;
        if (label_length > min_chars * 1.5) {
            ((!) label_widget).width_chars = min_chars;
            ((!) label_widget).ellipsize = Pango.EllipsizeMode.MIDDLE;
        } else {
            ((!) label_widget).width_chars = -1;
            ((!) label_widget).ellipsize = Pango.EllipsizeMode.NONE;
        }
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/pathbar.ui")]
public class Pathbar : Gtk.Box {
    [GtkChild]
    private unowned Gtk.Box button_box;

    [GtkChild]
    private unowned Gtk.ScrolledWindow scrolled_window;

    public string path { get; set; default = "/"; }

    public signal void item_activated (string path);

    construct {
        notify["path"].connect (on_path_changed);
        on_path_changed ();
    }

    [GtkCallback]
    private void on_adjustment_changed (Gtk.Adjustment adjusment) {
        const uint DURATION = 800;
        var target = new Adw.PropertyAnimationTarget (adjusment, "value");
        var animation = new Adw.TimedAnimation (this, adjusment.value, adjusment.upper, DURATION, target);
        animation.easing = Adw.Easing.EASE_OUT_CUBIC;
        animation.play ();
    }

    [GtkCallback]
    private void on_page_size_changed (Object o, ParamSpec spec) {
        var adjustment = (Gtk.Adjustment) o;
        // When window is resized, immediately set new value, otherwise we would get
        // an underflow gradient for an moment.
        adjustment.value = adjustment.upper;
    }

    [GtkCallback]
    private bool on_scrolled_window_scroll (Gtk.EventControllerScroll scroll, double dx, double dy) {
        if (dy == 0)
            return Gdk.EVENT_PROPAGATE;

        /* Scroll horizontally when vertically scrolled */
        Gtk.Adjustment hadjustment = scrolled_window.get_hadjustment ();
        double step = hadjustment.get_step_increment ();
        double new_value = hadjustment.get_value () + dy * step;
        hadjustment.set_value (new_value);

        return Gdk.EVENT_STOP;
    }

    private void on_path_changed ()
    {
        clear ();

        List<PathButton> buttons = new List<PathButton>();
        // path.find ("/");
        // string [] path_parts = path.split ("/", 0);
        int path_length = path[-1] == '/' ? path.length - 1 : path.length;

        int index = 0;

        while (index >= 0)
        {
            int next_index = path.index_of ("/", index);

            string full_path = (next_index == -1) ? path[0:] : path[0:next_index+1];
            string label = (next_index == -1) ? path[index:] : path[index:next_index];

            if (next_index == -1 || next_index == path_length - 1) {
                buttons.append (make_button (full_path, label, true));
                next_index = -1;
            } else {
                buttons.append (make_button (full_path, label, false));
                next_index += 1;
            }

            index = next_index;
        }

        bool first_directory = true;
        foreach (var button in buttons) {
            Gtk.Box box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            if (!first_directory) {
                Gtk.Label label = new Gtk.Label (GLib.Path.DIR_SEPARATOR_S);
                label.add_css_class ("dim-label");
                box.append (label);
            }
            box.append (button);
            button_box.append (box);
            first_directory = false;
        }
    }

    internal void get_complete_path (out string _complete_path) {
        // FIXME !
        _complete_path = "/";
    }

    internal void get_fallback_path_and_complete_path (out string _fallback_path, out string _complete_path)
    {
        // FIXME !!!!
        _fallback_path = "/";
        _complete_path = "/";
    }

    internal void update_ghosts (string non_ghost_path, bool is_search) {
        // FIXME !!!!!!
    }

    internal string get_selected_child (string current_path)
    {
        // FIXME
        return "";
    }

    void clear () {
        for (Gtk.Widget? child = button_box.get_first_child (); child != null; child = button_box.get_first_child ()) {
            button_box.remove ((!) child);
        }
    }

    PathButton make_button (string full_path, string label, bool is_current_dir) {
        var button = new PathButton ();

        if (full_path == "/" && label == "")
            button.icon_name = "ca.desrt.dconf-editor-symbolic";
        else
            button.label = label;
        button.is_current_dir = is_current_dir;

        if (is_current_dir) {
            button.set_action_name ("browser.edit-location");
        } else {
            button.set_detailed_action_name ("browser.open-folder('" + full_path + "')");
        }

        return button;
    }
}
