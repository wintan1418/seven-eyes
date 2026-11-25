// Controllers needed on most pages are imported here and ship in the main
// bundle. The heavy ones (the preaching console, the projector, slide tools,
// song bank, live sessions…) are in LAZY_CONTROLLERS below: each becomes its
// own chunk, fetched the first time its data-controller appears on a page
// (lib/lazy_controllers.js). The service worker keeps every chunk for offline.
// New controller? Add it here — eagerly, or to LAZY_CONTROLLERS if it's big
// and only used on a few screens.

import { application } from "./application"
import { registerLazyControllers } from "../lib/lazy_controllers"

import AppUpdateController from "./app_update_controller"
application.register("app-update", AppUpdateController)

import AuthGateController from "./auth_gate_controller"
application.register("auth-gate", AuthGateController)

import AutoSubmitController from "./auto_submit_controller"
application.register("auto-submit", AutoSubmitController)

import AutoscrollController from "./autoscroll_controller"
application.register("autoscroll", AutoscrollController)

import ListenOptionsController from "./listen_options_controller"
application.register("listen-options", ListenOptionsController)

import ListenPillController from "./listen_pill_controller"
application.register("listen-pill", ListenPillController)

import ListenPlayerController from "./listen_player_controller"
application.register("listen-player", ListenPlayerController)

import ChapterSwipeController from "./chapter_swipe_controller"
application.register("chapter-swipe", ChapterSwipeController)

import CommentaryController from "./commentary_controller"
application.register("commentary", CommentaryController)

import SearchModeController from "./search_mode_controller"
application.register("search-mode", SearchModeController)

import DiffController from "./diff_controller"
application.register("diff", DiffController)

import FontSizeController from "./font_size_controller"
application.register("font-size", FontSizeController)

import GuideController from "./guide_controller"
application.register("guide", GuideController)

import HighlighterController from "./highlighter_controller"
application.register("highlighter", HighlighterController)

import InterlinearController from "./interlinear_controller"
application.register("interlinear", InterlinearController)

import LexiconController from "./lexicon_controller"
application.register("lexicon", LexiconController)

import MemorizeController from "./memorize_controller"
application.register("memorize", MemorizeController)

import NewStudyController from "./new_study_controller"
application.register("new-study", NewStudyController)

import NotesController from "./notes_controller"
application.register("notes", NotesController)

import OfflineController from "./offline_controller"
application.register("offline", OfflineController)

import PaneController from "./pane_controller"
application.register("pane", PaneController)

import PassagePickerController from "./passage_picker_controller"
application.register("passage-picker", PassagePickerController)

import PrintController from "./print_controller"
application.register("print", PrintController)

import ReaderController from "./reader_controller"
application.register("reader", ReaderController)

import VoiceChoiceController from "./voice_choice_controller"
application.register("voice-choice", VoiceChoiceController)

import ReaderHeaderController from "./reader_header_controller"
application.register("reader-header", ReaderHeaderController)

import SearchController from "./search_controller"
application.register("search", SearchController)

import DailyWordController from "./daily_word_controller"
application.register("daily-word", DailyWordController)

import ShareController from "./share_controller"
application.register("share", ShareController)

import SheetController from "./sheet_controller"
application.register("sheet", SheetController)

import SheetsController from "./sheets_controller"
application.register("sheets", SheetsController)

import ShortcutsController from "./shortcuts_controller"
application.register("shortcuts", ShortcutsController)

import SyncScrollController from "./sync_scroll_controller"
application.register("sync-scroll", SyncScrollController)

import ThemeController from "./theme_controller"
application.register("theme", ThemeController)

import TourController from "./tour_controller"
application.register("tour", TourController)

import TranslationPickerController from "./translation_picker_controller"
application.register("translation-picker", TranslationPickerController)

import VerseActionsController from "./verse_actions_controller"
application.register("verse-actions", VerseActionsController)

import VerseFocusController from "./verse_focus_controller"
application.register("verse-focus", VerseFocusController)

import VerseLinesController from "./verse_lines_controller"
application.register("verse-lines", VerseLinesController)

import VerseSelectController from "./verse_select_controller"
application.register("verse-select", VerseSelectController)

import WhatsNewController from "./whats_new_controller"
application.register("whats-new", WhatsNewController)

import XrefController from "./xref_controller"
application.register("xref", XrefController)

import OfflineStudiesController from "./offline_studies_controller"
application.register("offline-studies", OfflineStudiesController)

// Slide tools (phase 2B): scripture slides, presentations, seminar slides,
// service templates, order of service — each owns its dialog (studies/_slide_tools).
import RevealController from "./reveal_controller"
application.register("reveal", RevealController)

import TodayHeroController from "./today_hero_controller"
application.register("today-hero", TodayHeroController)

import TodayResumeController from "./today_resume_controller"
application.register("today-resume", TodayResumeController)

import ParallaxController from "./parallax_controller"
application.register("parallax", ParallaxController)

import SundayCardController from "./sunday_card_controller"
application.register("sunday-card", SundayCardController)

import ReadMoreController from "./read_more_controller"
application.register("read-more", ReadMoreController)

const LAZY_CONTROLLERS = {
  "ai-search": () => import("./ai_search_controller"),
  "console": () => import("./console_controller"),
  "console-library": () => import("./console_library_controller"),
  "console-live": () => import("./console_live_controller"),
  "console-media": () => import("./console_media_controller"),
  "console-preview": () => import("./console_preview_controller"),
  "console-tour": () => import("./console_tour_controller"),
  "faith-pane": () => import("./faith_pane_controller"),
  "faith-rewriter": () => import("./faith_rewriter_controller"),
  "give": () => import("./give_controller"),
  "glossary-filter": () => import("./glossary_filter_controller"),
  "last-service": () => import("./last_service_controller"),
  "live": () => import("./live_controller"),
  "live-follow": () => import("./live_follow_controller"),
  "media-library": () => import("./media_library_controller"),
  "offline-downloads": () => import("./offline_downloads_controller"),
  "order-of-service": () => import("./order_of_service_controller"),
  "paste-verses": () => import("./paste_verses_controller"),
  "plan-offline": () => import("./plan_offline_controller"),
  "preach-offline": () => import("./preach_offline_controller"),
  "presentation": () => import("./presentation_controller"),
  "presentation-import": () => import("./presentation_import_controller"),
  "preview": () => import("./preview_controller"),
  "quick-present": () => import("./quick_present_controller"),
  "rabbi": () => import("./rabbi_controller"),
  "remote": () => import("./remote_controller"),
  "remote-pad": () => import("./remote_pad_controller"),
  "root-words": () => import("./root_words_controller"),
  "scene": () => import("./scene_controller"),
  "screen-live": () => import("./screen_live_controller"),
  "screen-look": () => import("./screen_look_controller"),
  "scripture-set": () => import("./scripture_set_controller"),
  "search-page": () => import("./search_page_controller"),
  "seminar-builder": () => import("./seminar_builder_controller"),
  "service-templates": () => import("./service_templates_controller"),
  "past-services": () => import("./past_services_controller"),
  "service-reset": () => import("./service_reset_controller"),
  "setlist": () => import("./setlist_controller"),
  "share-card": () => import("./share_card_controller"),
  "shatter-slider": () => import("./shatter_slider_controller"),
  "song-bank": () => import("./song_bank_controller"),
  "song-editor": () => import("./song_editor_controller"),
  "sunday-ready": () => import("./sunday_ready_controller"),
  "today-flow": () => import("./today_flow_controller"),
  "word-reveal": () => import("./word_reveal_controller"),
}

registerLazyControllers(application, LAZY_CONTROLLERS)
