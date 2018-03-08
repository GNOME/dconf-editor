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

public abstract class SettingObject : Object
{
    public string name { get; construct; }
    public string full_name { get; construct; }

    public string casefolded_name { get; private construct; }
    public string parent_path { get; private construct; }
    construct
    {
        casefolded_name = name.casefold ();

        if (full_name.length < 2)
            parent_path = "/";
        else
        {
            string tmp_string = full_name.slice (0, full_name.last_index_of_char ('/'));

            if (full_name.has_suffix ("/"))
                parent_path = full_name.slice (0, tmp_string.last_index_of_char ('/') + 1);
            else
                parent_path = tmp_string + "/";
        }
    }
}

public class Directory : SettingObject
{
    public Directory (string full_name, string name)
    {
        Object (full_name: full_name, name: name);
    }
}

public abstract class Key : SettingObject
{
    public abstract string descriptor { owned get; }

    public string type_string { get; protected set; default = "*"; }
    public Variant properties { owned get; protected set; }

    public signal void value_changed ();

    protected static string key_to_description (string type)
    {
        switch (type)
        {
            case "b":
                return _("Boolean");
            case "s":
                return _("String");
            case "as":
                return _("String array");
            case "<enum>":
                return _("Enumeration");
            case "<flags>":
                return _("Flags");
            case "d":
                return _("Double");
            case "h":
                /* Translators: this handle type is an index; you may maintain the word "handle" */
                return _("D-Bus handle type");
            case "o":
                return _("D-Bus object path");
            case "ao":
                return _("D-Bus object path array");
            case "g":
                return _("D-Bus signature");
            case "y":       // TODO byte, bytestring, bytestring array
            case "n":
            case "q":
            case "i":
            case "u":
            case "x":
            case "t":
                return _("Integer");
            default:
                return type;
        }
    }

    protected static void get_min_and_max_string (out string min, out string max, string type_string)
    {
        switch (type_string)
        {
            // TODO %I'xx everywhere! but would need support from the spinbutton…
            case "y":
                min = "%hhu".printf (uint8.MIN);    // TODO format as in
                max = "%hhu".printf (uint8.MAX);    //   cool_text_value_from_variant()
                return;
            case "n":
                string? nullable_min = "%'hi".printf (int16.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'hi".printf (int16.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%hi".printf (int16.MIN));
                max = (!) (nullable_max ?? "%hi".printf (int16.MAX));
                return;
            case "q":
                string? nullable_min = "%'hu".printf (uint16.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'hu".printf (uint16.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%hu".printf (uint16.MIN));
                max = (!) (nullable_max ?? "%hu".printf (uint16.MAX));
                return;
            case "i":
                string? nullable_min = "%'i".printf (int32.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'i".printf (int32.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%i".printf (int32.MIN));
                max = (!) (nullable_max ?? "%i".printf (int32.MAX));
                return;     // TODO why is 'li' failing to display '-'?
            case "u":
                string? nullable_min = "%'u".printf (uint32.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'u".printf (uint32.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%u".printf (uint32.MIN));
                max = (!) (nullable_max ?? "%u".printf (uint32.MAX));
                return;     // TODO is 'lu' failing also?
            case "x":
                string? nullable_min = "%'lli".printf (int64.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'lli".printf (int64.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%lli".printf (int64.MIN));
                max = (!) (nullable_max ?? "%lli".printf (int64.MAX));
                return;
            case "t":
                string? nullable_min = "%'llu".printf (uint64.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'llu".printf (uint64.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%llu".printf (uint64.MIN));
                max = (!) (nullable_max ?? "%llu".printf (uint64.MAX));
                return;
            case "d":
                string? nullable_min = "%'g".printf (double.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'g".printf (double.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%g".printf (double.MIN));
                max = (!) (nullable_max ?? "%g".printf (double.MAX));
                return;
            case "h":
                string? nullable_min = "%'i".printf (int32.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'i".printf (int32.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%i".printf (int32.MIN));
                max = (!) (nullable_max ?? "%i".printf (int32.MAX));
                return;
            default: assert_not_reached ();
        }
    }

    public static string cool_text_value_from_variant (Variant variant, string type)        // called from subclasses and from KeyListBoxRow
    {
        switch (type)
        {
            case "b":
                return cool_boolean_text_value (variant.get_boolean (), false);
            // TODO %I'xx everywhere! but would need support from the spinbutton…
            case "y":
                return "%hhu (%s)".printf (variant.get_byte (), variant.print (false));     // TODO i18n problem here
            case "n":
                string? nullable_text = "%'hi".printf (variant.get_int16 ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%hi".printf (variant.get_int16 ()));
            case "q":
                string? nullable_text = "%'hu".printf (variant.get_uint16 ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%hu".printf (variant.get_uint16 ()));
            case "i":
                string? nullable_text = "%'i".printf (variant.get_int32 ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%i".printf (variant.get_int32 ()));           // TODO why is 'li' failing to display '-'?
            case "u":
                string? nullable_text = "%'u".printf (variant.get_uint32 ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%u".printf (variant.get_uint32 ()));
            case "x":
                string? nullable_text = "%'lli".printf (variant.get_int64 ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%lli".printf (variant.get_int64 ()));
            case "t":
                string? nullable_text = "%'llu".printf (variant.get_uint64 ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%llu".printf (variant.get_uint64 ()));
            case "d":
                string? nullable_text = "%'.12g".printf (variant.get_double ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%g".printf (variant.get_double ()));
            case "h":
                string? nullable_text = "%'i".printf (variant.get_handle ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%i".printf (variant.get_int32 ()));
            default: break;
        }
        if (type.has_prefix ("m"))
        {
            Variant? maybe_variant = variant.get_maybe ();
            if (maybe_variant == null)
                return cool_boolean_text_value (null, false);
            if (type == "mb")
                return cool_boolean_text_value (((!) maybe_variant).get_boolean (), false);
        }
        return variant.print (false);
    }

    public static string cool_boolean_text_value (bool? nullable_boolean, bool capitalized = true)
    {
        if (capitalized)
        {
            if (nullable_boolean == true)
                return _("True");
            if (nullable_boolean == false)
                return _("False");
            return _("Nothing");
        }
        else
        {
            if (nullable_boolean == true)
                return _("true");
            if (nullable_boolean == false)
                return _("false");
            /* Translators: "nothing" here is a keyword that should appear for consistence; please translate as "yourtranslation (nothing)" */
            return _("nothing");
        }
    }

    protected static bool show_min_and_max (string type)
    {
        return (type == "d" || type == "y" || type == "n" || type == "q" || type == "i" || type == "u" || type == "x" || type == "t");
    }

    public static uint64 get_variant_as_uint64 (Variant variant)
    {
        switch (variant.classify ())
        {
            case Variant.Class.BYTE:    return (int64) variant.get_byte ();
            case Variant.Class.UINT16:  return (int64) variant.get_uint16 ();
            case Variant.Class.UINT32:  return (int64) variant.get_uint32 ();
            case Variant.Class.UINT64:  return variant.get_uint64 ();
            default: assert_not_reached ();
        }
    }

    public static int64 get_variant_as_int64 (Variant variant)
    {
        switch (variant.classify ())
        {
            case Variant.Class.INT16:   return (int64) variant.get_int16 ();
            case Variant.Class.INT32:   return (int64) variant.get_int32 ();
            case Variant.Class.INT64:   return variant.get_int64 ();
            case Variant.Class.HANDLE:  return (int64) variant.get_handle ();
            default: assert_not_reached ();
        }
    }
}

public class DConfKey : Key
{
    public override string descriptor { owned get { return full_name; } }

    public DConfKey (DConf.Client client, string parent_full_name, string name, string type_string)
    {
        Object (full_name: parent_full_name + name, name: name, type_string: type_string);

        VariantBuilder builder = new VariantBuilder (new VariantType ("(ba{ss})"));     // TODO add VariantBuilder add_parsed () function in vala/glib-2.0.vapi line ~5490
        builder.add ("b",    false);
        builder.open (new VariantType ("a{ss}"));
        builder.add ("{ss}", "key-name",    name);
        builder.add ("{ss}", "defined-by",  _("DConf backend"));
        builder.add ("{ss}", "parent-path", parent_full_name);
        builder.add ("{ss}", "type-code",   type_string);
        builder.add ("{ss}", "type-name",   key_to_description (type_string));
        if (show_min_and_max (type_string))
        {
            string min, max;
            get_min_and_max_string (out min, out max, type_string);

            builder.add ("{ss}", "minimum", min);
            builder.add ("{ss}", "maximum", max);
        }
        builder.close ();
        properties = builder.end ();

        client.changed.connect ((client, prefix, changes, tag) => {
                foreach (string item in changes)
                    if (prefix + item == full_name)
                    {
                        value_changed ();
                        return;
                    }
            });
    }
}

public class GSettingsKey : Key
{
    public bool warning_conflicting_key = false;
    public bool error_hard_conflicting_key = false;

    public string schema_id              { get; construct; }
    public string? schema_path   { private get; construct; }
    public string summary                { get; construct; }
    public string description    { private get; construct; }
    public Variant default_value         { get; construct; }
    public string range_type             { get; construct; }
    public Variant range_content         { get; construct; }

    public override string descriptor {
        owned get {
            if (schema_path == null)
                return @"$schema_id:$parent_path $name";
            return @"$schema_id $name";
        }
    }

    public GLib.Settings settings { get; construct; }

    public GSettingsKey (string parent_full_name, string name, GLib.Settings settings, string schema_id, string? schema_path, string summary, string description, string type_string, Variant default_value, string range_type, Variant range_content)
    {
        string? summary_nullable = summary.locale_to_utf8 (-1, null, null, null);
        summary = summary_nullable ?? summary;

        string? description_nullable = description.locale_to_utf8 (-1, null, null, null);
        description = description_nullable ?? description;

        Object (full_name: parent_full_name + name,
                name: name,
                settings : settings,
                // schema infos
                schema_id: schema_id,
                schema_path: schema_path,
                summary: summary,
                description: description,
                default_value: default_value,       // TODO devel default/admin default
                range_type: range_type,
                range_content: range_content);

        settings.changed [name].connect (() => value_changed ());

        this.type_string = type_string;

        string defined_by = schema_path == null ? _("Relocatable schema") : _("Schema with path");

        VariantBuilder builder = new VariantBuilder (new VariantType ("(ba{ss})"));
        builder.add ("b",    true);
        builder.open (new VariantType ("a{ss}"));
        builder.add ("{ss}", "key-name",    name);
        builder.add ("{ss}", "defined-by",  defined_by);
        builder.add ("{ss}", "parent-path", parent_full_name);
        builder.add ("{ss}", "type-code",   type_string);
        builder.add ("{ss}", "type-name",   key_to_description (type_string));
        builder.add ("{ss}", "schema-id",   schema_id);
        builder.add ("{ss}", "summary",     summary);
        builder.add ("{ss}", "description", description);
        builder.add ("{ss}", "default-value", cool_text_value_from_variant (default_value, type_string));
        if (show_min_and_max (type_string))
        {
            string min, max;
            if (range_type == "range")     // TODO test more; and what happen if only min/max is in range?
            {
                min = cool_text_value_from_variant (range_content.get_child_value (0), type_string);
                max = cool_text_value_from_variant (range_content.get_child_value (1), type_string);
            }
            else
                get_min_and_max_string (out min, out max, type_string);

            builder.add ("{ss}", "minimum", min);
            builder.add ("{ss}", "maximum", max);
        }
        builder.close ();
        properties = builder.end ();
    }
}

