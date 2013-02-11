// The renderer processes a sequence of timepoints, and executes a
// list of commands at each time point

// The internal frame is at the resolution of the first display
// target, best to make that the one the subject is seeing.
// It will be resized for the other displays

#ifdef CHICKEN
typedef long Window;
typedef void* Imlib_Image;
#endif

#define VIDEO_IDS 10

struct ffmpeg_video_t;
struct ffmpeg_video_t *ffmpeg_open_video(char* filename);

enum renderer_command_t {
  /* advance the sequence in at most this many s computed form the
     start of the current time step */
  RC_ADVANCE,
  /* play an audio file in the background, does not delay the sequence */
  RC_PLAY_AUDIO,                // not implemented
  /* wait for the audio stream to finish */
  RC_WAIT_FOR_AUDIO,            // not implemented
  /* speak with flite */
  RC_SPEAK_AUDIO,               // not implemented
  /* wait for flite to finish */
  RC_WAIT_FOR_SPEAK_AUDIO,      // not implemented
  /* flood fill a rectangle */
  RC_FILL_RECTANGLE,
  /* load a video file, currently only one can be active at one time */
  /* coordinates are normalized to the viewer size */
  RC_LOAD_VIDEO,
  RC_SHOW_VIDEO_FRAME,
  RC_ADVANCE_VIDEO_FRAME,
  /* render an image, coordinates are normalized to the viewer size */
  RC_IMAGE,
  /* replace the entire framebuffer with an image, fast */
  RC_REPLACE_WITH_IMAGE,        // not implemented
  /* draw text to the screen, coordinates and size are normalized to the viewer screen */
  /* size=1 text height is equal to screen height */
  RC_TEXT,
  /* reset brain volume counter, do before RC_WAIT_FOR_VOLUME */
  RC_START_VOLUME,
  /* wait for a new brain volume to start */
  RC_WAIT_FOR_VOLUME,
  /* stop the current iteration (ignoring loop counters), optionally clear the volume flag */
  RC_STOP_ON_VOLUME_WITHOUT_CLEARING,
  RC_STOP_ON_VOLUME_AND_CLEAR,
  /* wait for a button press */
  RC_BUTTONPRESS,           // not implemented
  /* sleep, won't delay past renderer_advance_t */
  /* always sleeps from the beginning of the current iteration */
  RC_SLEEP,
  /* render to the screen, without this it will leave up the last
     display and all draws will go into the framebuffer */
  RC_RENDER,
  /* wake up the gui with an X event */
  RC_WAKE_GUI,
  /* repeat the commands for n timepoints */
  RC_LOOP
};

// command arguments
// rc_ -> renderer_command_

struct rc_advance_t {
  double s;
};
struct rc_play_audio_t {
  char *filename;
};
struct rc_load_video_t {
  struct ffmpeg_video_t *ffmpeg_video;
  int id;
};
struct rc_show_video_frame_t {
  int id;
  double x, y, width, height;
  int a;
};
struct rc_advance_video_frame_t {
  int id;
};
struct rc_fill_rectangle_t {
  double x, y, width, height;
  int r, g, b, a; // 256
};
struct rc_image_t {
  Imlib_Image image;
  double x, y, width, height;
};
struct rc_sleep_t {
  double s;
};
// remember to set up imlib_add_path_to_font_path so that imlib can
// find the fonts
struct rc_text_t {
  char *text; char *font;
  // Note that you need to encode the size in the font name!
  // And that this is not independent of the framebuffer size unlike
  // all other measurements
  int r, g, b, a;
  int direction; double angle;
  double x, y;
};
struct rc_wake_gui_t {
  Window window;
};
struct rc_loop_t {
  int iterations;
};

// communication

struct renderer_commands_t {
  enum renderer_command_t type;
  void *data;
  struct renderer_commands_t *next;
};

struct renderer_sequence_t {
  struct renderer_commands_t *commands;
  struct renderer_sequence_t *next;
};

struct renderer_target_t {
  Window window;
  int width, height, x, y;
};

struct renderer_arguments_t {
  struct renderer_sequence_t *sequence;
  int sequence_length;
  struct renderer_target_t *targets;
  int nr_targets;
  // when done send an xevent to this window, scheme will resume
  Window wakeup_target;
};

enum stop_reason_t {
  RENDERER_FINISHED_SEQUENCE,
  RENDERER_WAS_STOPPED
};

struct renderer_log_t {
  double start_timestamp;
  int volume;
};

struct renderer_result_t {
  enum stop_reason_t stop_reason;
  int timepoints_processed;
  struct renderer_log_t *log;
};

// API

// this is read-only as far as scheme is concerned
extern volatile int renderer_stopped;

void setup_number_keys(int slices_per_tr);

void start_renderer(struct renderer_arguments_t *args);
struct renderer_result_t *stop_renderer();
void free_renderer_arguments(struct renderer_arguments_t *a);
