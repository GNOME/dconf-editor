/*
  This file is part of Dconf Editor

  Dconf Editor is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Dconf Editor is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with Dconf Editor.  If not, see <https://www.gnu.org/licenses/>.
*/

using Gtk;

private interface BrowserContent : Widget, AdaptativeWidget
{
    [CCode (notify = false)] internal abstract ViewType current_view { internal get; protected set; }

    internal abstract void prepare_folder_view (GLib.ListStore key_model, bool is_ancestor);
    internal abstract void prepare_object_view (string full_name, uint16 context_id, Variant properties, bool is_parent);
    internal abstract void set_path (ViewType type, string path);

    /*\
    * * current row stuff
    \*/

    internal abstract string get_selected_row_name ();
    internal abstract void select_row_named (string selected, uint16 last_context_id, bool grab_focus_if_needed);
    internal abstract void select_first_row ();
    internal abstract void row_grab_focus ();
    /*\
    * * popovers
    \*/

    internal abstract bool toggle_row_popover ();
    internal abstract void discard_row_popover ();
    internal abstract void invalidate_popovers ();

    /*\
    * * reload
    \*/

    internal abstract bool check_reload_folder (Variant? fresh_key_model);
    internal abstract bool check_reload_object (uint properties_hash);

    /*\
    * * keyboard calls
    \*/

    internal abstract bool handle_copy_text (out string copy_text);     // <Ctrl>c
    internal abstract bool handle_alt_copy_text (out string copy_text); // <Ctrl>C

    internal abstract bool next_match ();                               // <Ctlr>g
    internal abstract bool previous_match ();                           // <Ctrl>G

    internal abstract bool return_pressed ();                           // Return or KP_Enter
}
