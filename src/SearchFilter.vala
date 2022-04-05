/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

// Bitfield values used to specify which search bar features we want.
[Flags]
public enum SearchFilterCriteria {
    NONE = 0,
    RECURSIVE,
    TEXT,
    FLAG,
    MEDIA,
    RATING,
    SAVEDSEARCH,
    ALL = 0xFFFFFFFF
}

public enum RatingFilter {
    NO_FILTER = 0,
    REJECTED_OR_HIGHER = 1,
    UNRATED_OR_HIGHER = 2,
    ONE_OR_HIGHER = 3,
    TWO_OR_HIGHER = 4,
    THREE_OR_HIGHER = 5,
    FOUR_OR_HIGHER = 6,
    FIVE_OR_HIGHER = 7,
    REJECTED_ONLY = 8,
    UNRATED_ONLY = 9,
    ONE_ONLY = 10,
    TWO_ONLY = 11,
    THREE_ONLY = 12,
    FOUR_ONLY = 13,
    FIVE_ONLY = 14
}

 // Handles filtering via rating and text.
public abstract class SearchViewFilter : ViewFilter {
    // If this is true, allow the current rating or higher.
    private bool rating_allow_higher = true;
    
    // Rating to filter by.
    private Rating rating = Rating.UNRATED;
    private RatingFilter rating_filter = RatingFilter.UNRATED_OR_HIGHER;
    
    // Show flagged only if set to true.
    public bool flagged { get; set; default = false; }
    
    // Media types.
    public bool show_media_video { get; set; default = true; }
    public bool show_media_photos { get; set; default = true; }
    public bool show_media_raw { get; set; default = true; }
    
    // Search text filter.  Should only be set to lower-case.
    private string? search_filter = null;
    private string[]? search_filter_words = null;

    // Saved search filter
    public SavedSearch saved_search { get; set; default = null; }
    
    // Returns a bitmask of SearchFilterCriteria.
    // IMPORTANT: There is no signal on this, changing this value after the
    // view filter is installed will NOT update the GUI.
    public abstract uint get_criteria();
    
    public void set_rating_filter(RatingFilter rf) {
        rating_filter = rf;
        switch (rating_filter) {
            case RatingFilter.REJECTED_ONLY:
                rating = Rating.REJECTED;
                rating_allow_higher = false;
            break;
            
            case RatingFilter.REJECTED_OR_HIGHER:
                rating = Rating.REJECTED;
                rating_allow_higher = true;
            break;
            
            case RatingFilter.ONE_OR_HIGHER:
                rating = Rating.ONE;
                rating_allow_higher = true;
            break;
            
            case RatingFilter.ONE_ONLY:
                rating = Rating.ONE;
                rating_allow_higher = false;
            break;
            
            case RatingFilter.TWO_OR_HIGHER:
                rating = Rating.TWO;
                rating_allow_higher = true;
            break;
            
             case RatingFilter.TWO_ONLY:
                rating = Rating.TWO;
                rating_allow_higher = false;
            break;
            
            case RatingFilter.THREE_OR_HIGHER:
                rating = Rating.THREE;
                rating_allow_higher = true;
            break;
            
            case RatingFilter.THREE_ONLY:
                rating = Rating.THREE;
                rating_allow_higher = false;
            break;
            
            case RatingFilter.FOUR_OR_HIGHER:
                rating = Rating.FOUR;
                rating_allow_higher = true;
            break;
            
            case RatingFilter.FOUR_ONLY:
                rating = Rating.FOUR;
                rating_allow_higher = false;
            break;
            
            case RatingFilter.FIVE_OR_HIGHER:
                rating = Rating.FIVE;
                rating_allow_higher = true;
            break;
            
            case RatingFilter.FIVE_ONLY:
                rating = Rating.FIVE;
                rating_allow_higher = false;
            break;
            
            case RatingFilter.UNRATED_OR_HIGHER:
            default:
                rating = Rating.UNRATED;
                rating_allow_higher = true;
            break;
        }
    }
    
    public bool has_search_filter() {
        return !is_string_empty(search_filter);
    }
    
    public unowned string? get_search_filter() {
        return search_filter;
    }
       
    public unowned string[]? get_search_filter_words() {
        return search_filter_words;
    }
    
    public void set_search_filter(string? text) {
        search_filter = !is_string_empty(text) ? String.remove_diacritics(text.down()) : null;
        search_filter_words = search_filter != null ? search_filter.split(" ") : null;
    }
    
    public void clear_search_filter() {
        search_filter = null;
        search_filter_words = null;
    }
    
    public bool has_saved_search() {
        return saved_search != null;
    }

    public bool get_rating_allow_higher() {
        return rating_allow_higher;
    }
    
    public Rating get_rating() {
        return rating;
    }
    
    public bool filter_by_media_type() {
        return ((show_media_video || show_media_photos || show_media_raw) && 
            !(show_media_video && show_media_photos && show_media_raw));
    }
}

// This class provides a default predicate implementation used for CollectionPage
// as well as Trash and Offline.
public abstract class DefaultSearchViewFilter : SearchViewFilter {
    public override bool predicate(DataView view) {
        MediaSource source = ((Thumbnail) view).get_media_source();
        uint criteria = get_criteria();
        
        // Ratings filter
        if ((SearchFilterCriteria.RATING & criteria) != 0) {
            if (get_rating_allow_higher() && source.get_rating() < get_rating())
                return false;
            else if (!get_rating_allow_higher() && source.get_rating() != get_rating())
                return false;
        }
        
        // Flag state.
        if ((SearchFilterCriteria.FLAG & criteria) != 0) {
            if (flagged && source is Flaggable && !((Flaggable) source).is_flagged())
                return false;
        }
        
        // Media type.
        if (((SearchFilterCriteria.MEDIA & criteria) != 0) && filter_by_media_type()) {
            if (source is VideoSource) {
                if (!show_media_video)
                    return false;
            } else if (source is Photo) {
                Photo photo = source as Photo;
                if (photo.get_master_file_format() == PhotoFileFormat.RAW) {
                    if (!show_media_photos && !show_media_raw)
                        return false;
                } else if (!show_media_photos)
                    return false;
            }
        }
        
        // Text
        if (((SearchFilterCriteria.TEXT & criteria) != 0) && has_search_filter()) {
            unowned string? media_keywords = source.get_indexable_keywords();
            
            unowned string? event_keywords = null;
            Event? event = source.get_event();
            if (event != null)
                event_keywords = event.get_indexable_keywords();
            
            Gee.List<Tag>? tags = Tag.global.fetch_for_source(source);
            int tags_size = (tags != null) ? tags.size : 0;
 
#if ENABLE_FACES           
            Gee.List<Face>? faces = Face.global.fetch_for_source(source);
#endif
            
            foreach (unowned string word in get_search_filter_words()) {
                if (media_keywords != null && media_keywords.contains(word))
                    continue;
                
                if (event_keywords != null && event_keywords.contains(word))
                    continue;
                
                if (tags_size > 0) {
                    bool found = false;
                    for (int ctr = 0; ctr < tags_size; ctr++) {
                        unowned string? tag_keywords = tags[ctr].get_indexable_keywords();
                        if (tag_keywords != null && tag_keywords.contains(word)) {
                            found = true;
                            
                            break;
                        }
                    }
                    
                    if (found)
                        continue;
                }
                
#if ENABLE_FACES
                if (faces != null) {
                    bool found = false;
                    foreach (Face f in faces) {
                        unowned string? face_keywords = f.get_indexable_keywords();
                        if (face_keywords != null && face_keywords.contains(word)) {
                            found = true;
                            
                            break;
                        }
                    }
                    
                    if (found)
                        continue;
                }
#endif                
                // failed all tests (this even works if none of the Indexables have strings,
                // as they fail the implicit AND test)
                return false;
            }
        }
        
        // Saved search
        if (((SearchFilterCriteria.SAVEDSEARCH & criteria) != 0) && has_saved_search()) {
            return saved_search.predicate(source);
        }

        return true;
    }
}

public class DisabledViewFilter : SearchViewFilter {
    public override bool predicate(DataView view) {
        return true;
    }
    
    public override uint get_criteria() {
        return SearchFilterCriteria.RATING;
    }
}

public class TextAction {
    public string? value {
        get {
            return text;
        }
    }
    
    private string? text = null;
    private bool sensitive = true;
    private bool visible = true;
    
    public signal void text_changed(string? text);
    
    public signal void sensitivity_changed(bool sensitive);
    
    public signal void visibility_changed(bool visible);
    
    public TextAction(string? init = null) {
        text = init;
    }
    
    public void set_text(string? text) {
        if (this.text != text) {
            this.text = text;
            text_changed(text);
        }
    }
    
    public void clear() {
        set_text(null);
    }
    
    public bool is_sensitive() {
        return sensitive;
    }
    
    public void set_sensitive(bool sensitive) {
        if (this.sensitive != sensitive) {
            this.sensitive = sensitive;
            sensitivity_changed(sensitive);
        }
    }
    
    public bool is_visible() {
        return visible;
    }
    
    public void set_visible(bool visible) {
        if (this.visible != visible) {
            this.visible = visible;
            visibility_changed(visible);
        }
    }
}


public class SearchFilterActions {
    public unowned GLib.SimpleAction? flagged {
        get {
            return get_action ("display.flagged");
        }
    }
    
    public unowned GLib.SimpleAction? photos {
        get {
            return get_action ("display.photos");
        }
    }
    
    public unowned GLib.SimpleAction? videos {
        get {
            return get_action ("display.videos");
        }
    }
    
    public unowned GLib.SimpleAction? raw {
        get {
            return get_action ("display.raw");
        }
    }
    
    public unowned GLib.SimpleAction? rating {
        get {
            return get_action ("display.rating");
        }
    }
    
    public unowned TextAction text {
        get {
            assert(_text != null);
            return _text;
        }
    }
    
    private SearchFilterCriteria criteria = SearchFilterCriteria.ALL;
    private TextAction? _text = null;
    private bool has_flagged = true;
    private bool has_photos = true;
    private bool has_videos = true;
    private bool has_raw = true;
    private bool can_filter_by_stars = true;
    
    public signal void flagged_toggled(bool on);
    
    public signal void photos_toggled(bool on);
    
    public signal void videos_toggled(bool on);
    
    public signal void raw_toggled(bool on);
    
    public signal void rating_changed(RatingFilter filter);
    
    public signal void text_changed(string? text);

    
    /**
     * fired when the kinds of media present in the current view change (e.g., a video becomes
     * available in the view through a new import operation or no raw photos are available in
     * the view anymore because the last one was moved to the trash)
     */
    public signal void media_context_changed(bool has_photos, bool has_videos, bool has_raw,
        bool has_flagged);
    
    // Ticket #3290 - Hide some search bar fields when they
    // cannot be used.
    // Part 1 - we use this to announce when the criteria have changed,
    // and the toolbar can listen for it and hide or show widgets accordingly.
    public signal void criteria_changed();
    
    public SearchFilterActions() {
        // the getters defined above should not be used until register() returns
        register();
        
        text.text_changed.connect(on_text_changed);
    }
    
    public SearchFilterCriteria get_criteria() {
        return criteria;
    }

    public unowned GLib.ActionEntry[] get_actions () {
        return SearchFilterActions.entries;
    }
    
    public unowned GLib.SimpleAction? get_action(string name) {
        var lw = AppWindow.get_instance () as LibraryWindow;
        if (lw != null) {
            return lw.lookup_action (name) as GLib.SimpleAction;
        }

        return null;
        //    return action_group.lookup_action(name) as GLib.SimpleAction;
    }
    
    public void set_action_sensitive (string name, bool sensitive) {
        var action = get_action(name);
        if (action != null) {
            action.set_enabled (sensitive);
        }
    }
    
    public void reset() {
        flagged.change_state (false);
        photos.change_state (false);
        raw.change_state (false);
        videos.change_state (false);
        Variant v = "%d".printf (RatingFilter.UNRATED_OR_HIGHER);
        rating.change_state (v);

        text.set_text(null);
    }
    
    public void set_sensitive_for_search_criteria(SearchFilterCriteria criteria) {
        this.criteria = criteria;
        update_sensitivities();
        
        // Announce that we've gotten a new criteria...
        criteria_changed();
    }
    
    public void monitor_page_contents(Page? old_page, Page? new_page) {
        CheckerboardPage? old_tracked_page = old_page as CheckerboardPage;
        if (old_tracked_page != null) {
            Core.ViewTracker? tracker = old_tracked_page.get_view_tracker();
            if (tracker is MediaViewTracker)
                tracker.updated.disconnect(on_media_tracker_updated);
            else if (tracker is CameraViewTracker)
                tracker.updated.disconnect(on_camera_tracker_updated);
        }
        
        CheckerboardPage? new_tracked_page = new_page as CheckerboardPage;
        if (new_tracked_page != null) {
            can_filter_by_stars = true;
            
            Core.ViewTracker? tracker = new_tracked_page.get_view_tracker();
            if (tracker is MediaViewTracker) {
                tracker.updated.connect(on_media_tracker_updated);
                on_media_tracker_updated(tracker);
                
                return;
            } else if (tracker is CameraViewTracker) {
                tracker.updated.connect(on_camera_tracker_updated);
                on_camera_tracker_updated(tracker);
                
                return;
            }
        }
        
        // go with default behavior of making none of the filters available.
        has_flagged = false;
        has_photos = false;
        has_videos = false;
        has_raw = false;
        can_filter_by_stars = false;
        
        update_sensitivities();
    }
    
    private void on_media_tracker_updated(Core.Tracker t) {
        MediaViewTracker tracker = (MediaViewTracker) t;
        
        has_flagged = tracker.all.flagged > 0;
        has_photos = tracker.all.photos > 0;
        has_videos = tracker.all.videos > 0;
        has_raw = tracker.all.raw > 0;
        
        update_sensitivities();
    }
    
    private void on_camera_tracker_updated(Core.Tracker t) {
        CameraViewTracker tracker = (CameraViewTracker) t;
        
        has_flagged = false;
        has_photos = tracker.all.photos > 0;
        has_videos = tracker.all.videos > 0;
        has_raw = tracker.all.raw > 0;

        update_sensitivities();
    }
    
    private void update_sensitivities() {
        bool allow_ratings = (SearchFilterCriteria.RATING & criteria) != 0;
        set_action_sensitive("display.rating", allow_ratings & can_filter_by_stars);

        // Ticket #3343 - Don't disable the text field, even
        // when no searchable items are available.
        text.set_sensitive(true);
        
        media_context_changed(has_photos, has_videos, has_raw, has_flagged);
    }
    
    private void on_text_changed(TextAction action, string? text) {
        text_changed(text);
    }

    private const GLib.ActionEntry[] entries = {
        { "display.rating", on_action_radio, "s", "'2'", on_rating_changed },
        { "display.flagged", on_action_toggle, null, "false", on_flagged_toggled },
        { "display.photos", on_action_toggle, null, "false", on_photos_toggled },
        { "display.videos", on_action_toggle, null, "false", on_videos_toggled },
        { "display.raw", on_action_toggle, null, "false", on_raw_toggled }
    };

    private void on_action_radio (GLib.SimpleAction action,
                                  GLib.Variant?     parameter) {
        action.change_state (parameter);
    }

    private void on_action_toggle (GLib.SimpleAction action,
                                   GLib.Variant?     parameter) {
        var state = (bool) action.get_state ();
        action.change_state (!state);
    }
    
    private void register() {
        _text = new TextAction();
    }

    private void on_rating_changed (GLib.SimpleAction action,
                                    GLib.Variant      value) {
        if (value.get_string () == action.get_state().get_string ())
            return;

        var filter = (RatingFilter) int.parse (value.get_string ());
        action.set_state (value);
        rating_changed(filter);
    }
    
    private void on_flagged_toggled (GLib.SimpleAction action,
                                     GLib.Variant      value) {
        action.set_state (value);
        flagged_toggled (value.get_boolean ());
    }
    
    private void on_photos_toggled (GLib.SimpleAction action,
                                    GLib.Variant      value) {
        action.set_state (value);
        photos_toggled (value.get_boolean ());
    }
    
    private void on_videos_toggled (GLib.SimpleAction action,
                                    GLib.Variant      value) {
        action.set_state (value);
        videos_toggled (value.get_boolean ());
    }
    
    private void on_raw_toggled (GLib.SimpleAction action,
                                 GLib.Variant      value) {
        action.set_state (value);
        raw_toggled (value.get_boolean ());
    }
    
    public bool get_has_photos() {
        return has_photos;
    }
    
    public bool get_has_videos() {
        return has_videos;
    }
    
    public bool get_has_raw() {
        return has_raw;
    }
    
    public bool get_has_flagged() {
        return has_flagged;
    }
}

public class SearchFilterToolbar : Gtk.Box {
    private const int FILTER_BUTTON_MARGIN = 12; // the distance between icon and edge of button
    private const float FILTER_ICON_STAR_SCALE = 0.65f; // changes the size of the filter icon
    private const float FILTER_ICON_SCALE = 0.75f; // changes the size of the all photos icon
    
    // filter_icon_base_width is the width (in px) of a single filter icon such as one star or an "X"
    private const int FILTER_ICON_BASE_WIDTH = 30;
    // filter_icon_plus_width is the width (in px) of the plus icon
    private const int FILTER_ICON_PLUS_WIDTH = 20;
    
    private class LabelToolItem : Gtk.Box {
        private Gtk.Label label;
        
        public LabelToolItem(string s, int left_padding = 0, int right_padding = 0) {
            label = new Gtk.Label(s);
            if (left_padding != 0 || right_padding != 0) {
                label.halign = Gtk.Align.START;
                label.valign = Gtk.Align.CENTER;
                label.margin_start = left_padding;
                label.margin_end = right_padding;
            }
            append (label);
        }
    }
    
    private class ToggleActionToolButton : Gtk.Box {
        private Gtk.ToggleButton button;
        private Gtk.Image image;
        private Gtk.Label label;

        public ToggleActionToolButton(string action) {
            var content = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            image = new Gtk.Image();
            label = new Gtk.Label(null);
            content.prepend(image);
            content.append(label);
            image.set_visible(false);
            label.set_visible(false);
            button = new Gtk.ToggleButton();
            button.set_can_focus(false);
            button.set_action_name (action);
            button.set_has_tooltip(true);
            button.set_margin_start(2);
            button.set_child(content);
            
            this.append (button);
        }
        
        public void set_icon_name(string icon_name) {
            if (button.get_label() != "" && button.get_label() != null) {
                image.margin_end = 6;
            }
            image.set_from_icon_name(icon_name);
            image.set_visible(true);
        }

        public void set_label(string label) {
            this.label.set_text(label);
            this.label.set_visible(true);
        }

    }
    
    // Ticket #3260 - Add a 'close' context menu to
    // the searchbar.
    // The close menu. Populated below in the constructor.
    #if 0
    private Gtk.Menu close_menu = new Gtk.Menu();
    private Gtk.MenuItem close_item = new Gtk.MenuItem();
    #endif

    // Text search box.
    protected class SearchBox : Gtk.Box {
        private Gtk.SearchEntry search_entry;
        private TextAction action;
        
        public SearchBox(TextAction action) {
            this.action = action;
            search_entry = new Gtk.SearchEntry();
            
            search_entry.width_chars = 23;
            //search_entry.key_press_event.connect(on_escape_key); 
            append(search_entry);
            
            set_nullable_text(action.value);
            
            action.text_changed.connect(on_action_text_changed);
            action.sensitivity_changed.connect(on_sensitivity_changed);
            action.visibility_changed.connect(on_visibility_changed);
            
            search_entry.delete_text.connect(on_entry_changed);
            search_entry.insert_text.connect(on_entry_changed);
        }
        
        ~SearchBox() {
            action.text_changed.disconnect(on_action_text_changed);
            action.sensitivity_changed.disconnect(on_sensitivity_changed);
            action.visibility_changed.disconnect(on_visibility_changed);
            
            search_entry.delete_text.disconnect(on_entry_changed);
            search_entry.insert_text.disconnect(on_entry_changed);
        }
        
        public void get_focus() {
        }
        

        #if 0
        // Ticket #3124 - user should be able to clear 
        // the search textbox by typing 'Esc'. 
        private bool on_escape_key(Gdk.EventKey e) { 
            if(Gdk.keyval_name(e.keyval) == "Escape")
                action.clear();
            
           // Continue processing this event, since the 
           // text entry functionality needs to see it too. 
            return false; 
        }
        #endif
        
        private void on_action_text_changed(string? text) {
            //search_entry.get_buffer().buffer.deleted_text.disconnect(on_entry_changed);
            //search_entry.get_buffer().inserted_text.disconnect(on_entry_changed);
            set_nullable_text(text);
            //search_entry.buffer.deleted_text.connect(on_entry_changed);
            //search_entry.buffer.inserted_text.connect(on_entry_changed);
        }
        
        private void on_entry_changed() {
            action.text_changed.disconnect(on_action_text_changed);
            action.set_text(search_entry.get_text());
            action.text_changed.connect(on_action_text_changed);
        }
        
        private void on_sensitivity_changed(bool sensitive) {
            this.sensitive = sensitive;
        }
        
        private void on_visibility_changed(bool visible) {
            ((Gtk.Widget) this).visible = visible;
        }
        
        private void set_nullable_text(string? text) {
            search_entry.set_text(text != null ? text : "");
        }
    }
    
    // Handles ratings filters.
    protected class RatingFilterButton : Gtk.Box {
        public Gtk.MenuButton button;

        public RatingFilterButton(GLib.MenuModel model) {
            button = new Gtk.MenuButton();

            // TODO button.set_image (get_filter_icon(RatingFilter.UNRATED_OR_HIGHER));
            button.set_can_focus(false);
            button.set_margin_start(2);
            button.set_menu_model (model);

            set_homogeneous(false);

            this.append(button);
        }

        private Gtk.Widget get_filter_icon(RatingFilter filter) {
            Gtk.Widget? icon = null;

            switch (filter) {
                case RatingFilter.REJECTED_OR_HIGHER:
                    var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
                    var image = new Gtk.Image.from_icon_name ("emblem-photos-symbolic");
                    image.margin_end = 2;
                    box.append(image);
                    image = new Gtk.Image.from_icon_name ("window-close-symbolic");
                    box.append(image);
                    icon = box;
                    icon.show();
                break;
                
                case RatingFilter.REJECTED_ONLY:
                    icon = new Gtk.Image.from_icon_name ("window-close-symbolic");
                break;
                
                case RatingFilter.UNRATED_OR_HIGHER:
                default:
                    icon = new Gtk.Image.from_icon_name ("emblem-photos-symbolic");
                break;
            }

            icon.margin_end = 6;

            return icon;
        }

        private int get_filter_icon_size(RatingFilter filter) {
            int icon_base = (int) (FILTER_ICON_BASE_WIDTH * FILTER_ICON_SCALE);
            int icon_star_base = (int) (FILTER_ICON_BASE_WIDTH * FILTER_ICON_STAR_SCALE);
            int icon_plus = (int) (FILTER_ICON_PLUS_WIDTH * FILTER_ICON_STAR_SCALE);
            
            switch (filter) {
                case RatingFilter.ONE_OR_HIGHER:
                    return icon_star_base + icon_plus;
                case RatingFilter.TWO_OR_HIGHER:
                    return icon_star_base * 2 + icon_plus;
                case RatingFilter.THREE_OR_HIGHER:
                    return icon_star_base * 3 + icon_plus;
                case RatingFilter.FOUR_OR_HIGHER:
                    return icon_star_base * 4 + icon_plus;
                case RatingFilter.FIVE_OR_HIGHER:
                case RatingFilter.FIVE_ONLY:
                    return icon_star_base * 5;
                case RatingFilter.REJECTED_OR_HIGHER:
                    return Resources.ICON_FILTER_REJECTED_OR_BETTER_FIXED_SIZE;
                case RatingFilter.UNRATED_OR_HIGHER:
                    return Resources.ICON_FILTER_UNRATED_OR_BETTER_FIXED_SIZE;
                case RatingFilter.REJECTED_ONLY:
                    return icon_plus;
                default:
                    return icon_base;
            }
        }

        public void set_filter_icon(RatingFilter filter) {
            //button.set_always_show_image(true);
            switch (filter) {
            case RatingFilter.ONE_OR_HIGHER:
                button.set_label (_("★+ Rating"));
                break;
            case RatingFilter.TWO_OR_HIGHER:
                button.set_label (_("★★+ Rating"));
                break;
            case RatingFilter.THREE_OR_HIGHER:
                button.set_label (_("★★★+ Rating"));
                break;
            case RatingFilter.FOUR_OR_HIGHER:
                button.set_label (_("★★★★+ Rating"));
                break;
            case RatingFilter.FIVE_ONLY:
            case RatingFilter.FIVE_OR_HIGHER:
                button.set_label (_("★★★★★+ Rating"));
                break;
            default:
                button.set_label (_("Rating"));
                //button.set_image(get_filter_icon(filter));
                break;
            }

            set_size_request(get_filter_button_size(filter), -1);
            set_tooltip_text(Resources.get_rating_filter_tooltip(filter));
            set_has_tooltip(true);
            show();
        }

        private int get_filter_button_size(RatingFilter filter) {
            return get_filter_icon_size(filter) + 2 * FILTER_BUTTON_MARGIN;
        }

        public void set_label(string label) {
            button.set_label(label);
        }

    }

    protected class SavedSearchFilterButton : Gtk.Box {
        public SavedSearchPopover filter_popup = null;
        public Gtk.ToggleButton button;

        public signal void clicked();

        public SavedSearchFilterButton() {
            button = new Gtk.ToggleButton();

            Gtk.Image? image = new Gtk.Image.from_icon_name("edit-find-symbolic");
            image.set_margin_end(6);
            this.prepend (image);
            button.set_can_focus(false);

            button.clicked.connect(on_clicked);

            restyle();

            set_homogeneous(false);

            this.append(button);
        }

        ~SavedSearchFilterButton() {
            button.clicked.disconnect(on_clicked);
        }

        private void on_clicked() {
            clicked();
        }

        public void set_active(bool active) {
            button.set_active(active);
        }

        public void set_label(string label) {
            button.set_label(label);
        }

        public void restyle() {
			button.set_size_request(24, 24);
        }
    }

    public Gtk.Builder builder = new Gtk.Builder ();
    
    private SearchFilterActions actions;
    private SavedSearch saved_search = null;
    private SearchBox search_box;
    private RatingFilterButton rating_button;
    private SavedSearchFilterButton saved_search_button = new SavedSearchFilterButton();
    private bool elide_showing_again = false;
    private SearchViewFilter? search_filter = null;
    private LabelToolItem label_type;
    private ToggleActionToolButton toolbtn_photos;
    private ToggleActionToolButton toolbtn_videos;
    private ToggleActionToolButton toolbtn_raw;
    private ToggleActionToolButton toolbtn_flag;
    
    public SearchFilterToolbar(SearchFilterActions actions) {
        Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 6);
        this.actions = actions;
        actions.media_context_changed.connect(on_media_context_changed);
        search_box = new SearchBox(actions.text);
        add_css_class("toolbar");
        
        set_name("search-filter-toolbar");
        
        try {
            this.builder.add_from_resource (Resources.get_ui("search_bar.ui"));
        } catch (Error err) {
            AppWindow.panic(_("Error loading search bar UI: %s").printf(
                err.message));
        }
        
        // Ticket #3260 - Add a 'close' context menu to
        // the searchbar.
        // Prepare the close menu for use, but don't
        // display it yet; we'll connect it to secondary
        // click later on.
        #if 0
        close_item.set_label(_("Close"));
        close_item.show();
        close_item.activate.connect(on_context_menu_close_chosen);
        close_menu.append(close_item);
        #endif
       
        // Type label and toggles
        label_type = new LabelToolItem(_("Type"), 10, 5);
        append(label_type);
        
        toolbtn_photos = new ToggleActionToolButton("win.display.photos");
        toolbtn_photos.set_tooltip_text (_("Photos"));
        
        toolbtn_videos = new ToggleActionToolButton("win.display.videos");
        toolbtn_videos.set_tooltip_text(_("Videos"));
        
        toolbtn_raw = new ToggleActionToolButton("win.display.raw");
        toolbtn_raw.set_tooltip_text(_("RAW Photos"));
        
        append(toolbtn_photos);
        append(toolbtn_videos);
        append(toolbtn_raw);
        
        // separator
        append(new Gtk.Separator(Gtk.Orientation.VERTICAL));
        
        // Flagged button
        
        toolbtn_flag = new ToggleActionToolButton("win.display.flagged");
        toolbtn_flag.set_label(_("Flagged"));
        toolbtn_flag.set_tooltip_text(_("Flagged"));
        
        append(toolbtn_flag);
        
        // separator
        append(new Gtk.Separator(Gtk.Orientation.VERTICAL));
        
        // Rating button
        var model = this.builder.get_object ("popup-menu") as GLib.MenuModel;
        rating_button = new RatingFilterButton (model);
        rating_button.set_label(_("Rating"));
        append(rating_button);
        
        // separator
        append(new Gtk.Separator(Gtk.Orientation.VERTICAL));

        // Saved search button
		saved_search_button.set_label(_("Saved Search"));
        saved_search_button.set_tooltip_text(_("Use a saved search to filter items in the current view"));
        saved_search_button.clicked.connect(on_saved_search_button_clicked);
        append(saved_search_button);

        // separator
        var separator = new Gtk.Separator(Gtk.Orientation.VERTICAL);
        separator.hexpand = true;
        separator.halign = Gtk.Align.START;
        append(separator);
        
        // Search box.
        append(search_box);

        // hook up signals to actions to be notified when they change
        actions.flagged_toggled.connect(on_flagged_toggled);
        actions.photos_toggled.connect(on_photos_toggled);
        actions.videos_toggled.connect(on_videos_toggled);
        actions.raw_toggled.connect(on_raw_toggled);
        actions.rating_changed.connect(on_rating_changed);
        actions.text_changed.connect(on_search_text_changed);
        actions.criteria_changed.connect(on_criteria_changed);
        
        // #3260 part II Hook up close menu.
        //toolbar.popup_context_menu.connect(on_context_menu_requested);
        
        on_media_context_changed(actions.get_has_photos(), actions.get_has_videos(),
            actions.get_has_raw(), actions.get_has_flagged());
    }
    
    ~SearchFilterToolbar() {
        
        actions.media_context_changed.disconnect(on_media_context_changed);

        actions.flagged_toggled.disconnect(on_flagged_toggled);
        actions.photos_toggled.disconnect(on_photos_toggled);
        actions.videos_toggled.disconnect(on_videos_toggled);
        actions.raw_toggled.disconnect(on_raw_toggled);
        actions.rating_changed.disconnect(on_rating_changed);
        actions.text_changed.disconnect(on_search_text_changed);
        actions.criteria_changed.disconnect(on_criteria_changed);
        
        //toolbar.popup_context_menu.disconnect(on_context_menu_requested); 
    }
    
    private void on_media_context_changed(bool has_photos, bool has_videos, bool has_raw,
        bool has_flagged) {
        if (has_photos || has_raw)
            // As a user, I would expect, that a raw photo is still a photo.
            // Let's enable the photo button even if there are only raw photos.
            toolbtn_photos.set_icon_name("filter-photos-symbolic");
        else
            toolbtn_photos.set_icon_name("filter-photos-disabled-symbolic");

        if (has_videos)
            toolbtn_videos.set_icon_name("filter-videos-symbolic");
        else
            toolbtn_videos.set_icon_name("filter-videos-disabled-symbolic");

        if (has_raw)
            toolbtn_raw.set_icon_name("filter-raw-symbolic");
        else
            toolbtn_raw.set_icon_name("filter-raw-disabled-symbolic");

        if (has_flagged)
            toolbtn_flag.set_icon_name("filter-flagged-symbolic");
        else
            toolbtn_flag.set_icon_name("filter-flagged-disabled-symbolic");
    }
    
    // Ticket #3260 part IV - display the context menu on secondary click
    private bool on_context_menu_requested(int x, int y, int button) { 
        //close_menu.popup_at_pointer(null);
        return false;
    }
    
    // Ticket #3260 part III - this runs whenever 'close'
    // is chosen in the context menu.
    private void on_context_menu_close_chosen() { 
        AppWindow aw = LibraryWindow.get_app();        
        
        // Try to obtain the action for toggling the searchbar.  If
        // it's null, then we're probably in direct edit mode, and 
        // shouldn't do anything anyway.
        var action = aw.lookup_action ("CommonDisplaySearchbar") as
            GLib.SimpleAction;
        
        // Could we find the appropriate action?
        if(action != null) {
            // Yes, hide the search bar.
            action.change_state(false);
        }
    }
    
    private void on_flagged_toggled() {
        update();
    }
    
    private void on_videos_toggled() {
        update();
    }
    
    private void on_photos_toggled() {
        update();
    }
    
    private void on_raw_toggled() {
        update();
    }
    
    private void on_search_text_changed() {
        update();
    }

    private void on_rating_changed() {
        AppWindow aw = LibraryWindow.get_app();

        if (aw == null)
            return;

        var action = aw.lookup_action ("CommonDisplaySearchbar") as
            GLib.SimpleAction;

        // Could we find the appropriate action?
        if(action != null) {
            action.change_state(true);
        }

        update();
    }

    // Ticket #3290, part II - listen for criteria change signals,
    // and show or hide widgets based on the criteria we just 
    // changed to.
    private void on_criteria_changed() {
        update();
    }
    
    public void set_view_filter(SearchViewFilter search_filter) {
        if (search_filter == this.search_filter)
            return;
        
        this.search_filter = search_filter;
        
        // Enable/disable toolbar features depending on what the filter offers
        actions.set_sensitive_for_search_criteria((SearchFilterCriteria) search_filter.get_criteria());
        rating_button.sensitive = (SearchFilterCriteria.RATING & search_filter.get_criteria()) != 0;
        
        update();
    }
    
    public void unset_view_filter() {
        set_view_filter(new DisabledViewFilter());
    }
    
    // Forces an update of the search filter.
    public void update() {
        if (null == search_filter) {
            // Search bar isn't being shown, need to toggle it.
            LibraryWindow.get_app().show_search_bar(true);
        }
        
        assert(null != search_filter);
        
        search_filter.set_search_filter(actions.text.value);
        search_filter.flagged = actions.flagged.get_state ().get_boolean ();
        search_filter.show_media_video = actions.videos.get_state
            ().get_boolean ();
        search_filter.show_media_photos = actions.photos.get_state
            ().get_boolean ();
        search_filter.show_media_raw = actions.raw.get_state ().get_boolean ();

        var filter = (RatingFilter) int.parse (actions.rating.get_state ().get_string ());
        search_filter.set_rating_filter(filter);
        rating_button.set_filter_icon(filter);

        search_filter.saved_search = saved_search;
        
        // Ticket #3290, part III - check the current criteria
        // and show or hide widgets as needed.
        SearchFilterCriteria criteria = actions.get_criteria();
        
        search_box.visible = ((criteria & SearchFilterCriteria.TEXT) != 0);

        rating_button.visible = ((criteria & SearchFilterCriteria.RATING) != 0);
        
        toolbtn_flag.visible = ((criteria & SearchFilterCriteria.FLAG) != 0);
        
        label_type.visible = ((criteria & SearchFilterCriteria.MEDIA) != 0);
        toolbtn_photos.visible = ((criteria & SearchFilterCriteria.MEDIA) != 0); 
        toolbtn_videos.visible = ((criteria & SearchFilterCriteria.MEDIA) != 0);
        toolbtn_raw.visible = ((criteria & SearchFilterCriteria.MEDIA) != 0);

        saved_search_button.visible = ((criteria & SearchFilterCriteria.SAVEDSEARCH) != 0);

        // Ticket #3290, part IV - ensure that the separators
        // are shown and/or hidden as needed.
        //sepr_mediatype_flagged.visible = (label_type.visible && toolbtn_flag.visible);

        //sepr_flagged_rating.visible = ((label_type.visible && rating_button.visible) ||
        //    (toolbtn_flag.visible && rating_button.visible));

        // Send update to view collection.
        search_filter.refresh();
    }
    
    private void on_savedsearch_selected(SavedSearch saved_search) {
        this.saved_search = saved_search;
        update();
    }

    private void disable_savedsearch() {
        this.saved_search = null;
        update();
    }

    private void edit_dialog(SavedSearch search) {
        saved_search_button.filter_popup.hide();
        SavedSearchDialog ssd = new SavedSearchDialog.edit_existing(search);
        ssd.show();
    }

    private void delete_dialog(SavedSearch search) {
        saved_search_button.filter_popup.hide();
        Dialogs.confirm_delete_saved_search.begin(search, (source, res) => {
            if (Dialogs.confirm_delete_saved_search.end(res)) {
                AppWindow.get_command_manager().execute(new DeleteSavedSearchCommand(search));
            }
        });
    }

    private void add_dialog() {
        saved_search_button.filter_popup.hide();
        (new SavedSearchDialog()).show();
    }

    private void on_popover_closed() {
        // set_active emits clicked, so have a flag to not actually do anything
        elide_showing_again = true;
        saved_search_button.set_active(saved_search != null);
        saved_search_button.filter_popup.hide();
    }

    
    private void on_saved_search_button_clicked() {
        if (elide_showing_again && saved_search == null) {
        } else if (saved_search != null) {
            saved_search = null;
            saved_search_button.set_active(false);
            disable_savedsearch();
        } else {
            if (saved_search_button.filter_popup != null) {
                saved_search_button.filter_popup.edit_clicked.disconnect(edit_dialog);
                saved_search_button.filter_popup.search_activated.disconnect(on_savedsearch_selected);
                saved_search_button.filter_popup.delete_clicked.disconnect(delete_dialog);
                saved_search_button.filter_popup.add_clicked.disconnect(add_dialog);
                saved_search_button.filter_popup.closed.disconnect(on_popover_closed);
            }
            saved_search_button.filter_popup = new SavedSearchPopover();
            saved_search_button.filter_popup.popover.set_parent(saved_search_button);
            saved_search_button.filter_popup.edit_clicked.connect(edit_dialog);
            saved_search_button.filter_popup.search_activated.connect(on_savedsearch_selected);
            saved_search_button.filter_popup.delete_clicked.connect(delete_dialog);
            saved_search_button.filter_popup.add_clicked.connect(add_dialog);
            saved_search_button.filter_popup.closed.connect(on_popover_closed);
            saved_search_button.filter_popup.show_all();
        }
        elide_showing_again = false;
    }

    public void take_focus() {
        search_box.get_focus();
    }
}
