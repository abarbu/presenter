#include <pthread.h>
#include <stdio.h>
#include <sys/time.h>
#include <X11/Xlib.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <Imlib2.h>
#include "presenterlib-c.h"
#include <unistd.h>
#include <X11/Xlib.h>
#include <X11/Xproto.h>
#include <X11/X.h>
#include <X11/Xutil.h>
#include <X11/extensions/XInput2.h>

#define DEBUGGING 0

#if DEBUGGING
double max_time = 0;
#endif

#define presenter_error(...) {				\
    fprintf(stderr, "%s:%d: ", __FUNCTION__, __LINE__);	\
    fprintf(stderr, __VA_ARGS__);			\
    fprintf(stderr, "\n");				\
    exit(-1);						\
  }

pthread_t renderer_thread;
volatile int renderer_stopped = 1;
/* TODO: a hack just for tonight */
pthread_t trigger_thread;
volatile int first_trigger = 0;
/* have we collected a volume since the last time this was reset? */
volatile int volume = 0;
/* total number of volumes collected */
volatile int volumes = 0;
/* current trigger counter */
volatile int counter = 0;

void* renderer(void *args);

/* adapted from 
   test_xi2.c from xinput
   with references from
   http://people.freedesktop.org/~whot/xi2-recipes/part5.c */

struct number_keys_arguments_t {
  int slices_per_tr;
};

/* can't use AnyModifier, it's too often unavailable */

void grabKey(Display *dpy, Window root, int keycode) {
  XGrabKey(dpy, keycode, 0, root, False, GrabModeAsync, GrabModeAsync);
  XGrabKey(dpy, keycode, ControlMask, root, False, GrabModeAsync, GrabModeAsync);
  XGrabKey(dpy, keycode, ShiftMask, root, False, GrabModeAsync, GrabModeAsync);
  XGrabKey(dpy, keycode, ControlMask | ShiftMask, root, False, GrabModeAsync, GrabModeAsync);
  XGrabKey(dpy, keycode, LockMask, root, False, GrabModeAsync, GrabModeAsync);
  XGrabKey(dpy, keycode, ControlMask | LockMask, root, False, GrabModeAsync, GrabModeAsync);
  XGrabKey(dpy, keycode, ShiftMask | LockMask, root, False, GrabModeAsync, GrabModeAsync);
  XGrabKey(dpy, keycode, ControlMask | ShiftMask | LockMask, root, False, GrabModeAsync, GrabModeAsync);
}

void unGrabKey(Display *dpy, Window root, int keycode) {
  XUngrabKey(dpy, keycode, 0, root);
  XUngrabKey(dpy, keycode, ControlMask, root);
  XUngrabKey(dpy, keycode, ShiftMask, root);
  XUngrabKey(dpy, keycode, ControlMask | ShiftMask, root);
  XUngrabKey(dpy, keycode, LockMask, root);
  XUngrabKey(dpy, keycode, ControlMask | LockMask, root);
  XUngrabKey(dpy, keycode, ShiftMask | LockMask, root);
  XUngrabKey(dpy, keycode, ControlMask | ShiftMask | LockMask, root);
}

void sendKey(Display *dpy, Window root, int keycode) {
  XKeyEvent ke;
  ke.display = dpy;
  ke.root = root;
  ke.send_event = True;
  ke.subwindow = None;
  ke.time = CurrentTime;
  ke.x = 1;
  ke.y = 1;
  ke.x_root = 1;
  ke.y_root = 1;
  ke.same_screen = True;
  ke.type = KeyPress;
  ke.state = 0;
  ke.keycode = keycode;
  Window w; int x;
  XGetInputFocus(dpy, &w, &x);
  ke.window = w;
  XSendEvent(dpy, w, True, KeyPressMask, (XEvent*)&ke);
  XSync(dpy, False);
}

void* grab_number_keys(void *args_) {
  struct number_keys_arguments_t *args = args_;
  int slices_per_tr = args->slices_per_tr;

  Display*    dpy     = XOpenDisplay(0);
  Window      root    = DefaultRootWindow(dpy);
  XEvent      ev;

  int keycode5 = XKeysymToKeycode(dpy,XK_5);
  int keycodeT = XKeysymToKeycode(dpy,XK_T);

  grabKey(dpy, root, keycode5);
  grabKey(dpy, root, keycodeT);
  XSelectInput(dpy, root, KeyPressMask );
  
  while(1) {
    XNextEvent(dpy, &ev);
    if(ev.type == KeyPress) {
      XKeyEvent *ke = (XKeyEvent*)&ev;
      if(ke->keycode == keycode5 || ke->keycode == keycodeT) {
#if DEBUGGING
        printf("keypress\n");
#endif
        first_trigger = 1;
        if(counter == slices_per_tr - 1) {
          counter = 0;
          volume = 1;
          volumes++;
          printf("volume %d\n", volumes);
        } else {
          counter++;
        }
      } else {
        /* With simultaneous keypresses X delivers both of them to the
           listener, even if we didn't ask for them. So we send it
           back on its way. */
        sendKey(dpy, root, ke->keycode);
      }
    }
  }

  unGrabKey(dpy, root, keycode5);
  unGrabKey(dpy, root, keycodeT);
  XCloseDisplay(dpy);
  free(args_);
  return NULL;
}

void setup_number_keys(int slices_per_tr) {
  pthread_attr_t attributes;
  pthread_attr_init(&attributes);
  pthread_attr_setstacksize(&attributes, 10485760); /* hardwired 10MB */
  struct number_keys_arguments_t *arg =
    malloc(sizeof(struct number_keys_arguments_t));
  arg->slices_per_tr = slices_per_tr;
  if (pthread_create(&trigger_thread, &attributes, grab_number_keys, arg))
    presenter_error("Can't grab keys");
}

/* API */

void start_renderer(struct renderer_arguments_t *args) {
  if(!renderer_stopped)
    presenter_error("Can't start two renderers at once");
  /* counter variables */
  first_trigger = 0;
  volume = 0;
  volumes = 0;
  counter = 0;
  /* renderer */
  renderer_stopped = 0;
  pthread_attr_t attributes;
  pthread_attr_init(&attributes);
  pthread_attr_setstacksize(&attributes, 10485760); /* hardwired 10MB */
  if (pthread_create(&renderer_thread, &attributes, renderer, (void*)args))
    presenter_error("Can't presenter thread");
}

struct renderer_result_t *stop_renderer() {
  renderer_stopped = 1;
  struct renderer_result_t *result;
  if(pthread_join(renderer_thread, (void*)&result))
    presenter_error("Can't stop presenter thread");
  return result;
}

/* misc */

#ifndef MIN
#define MIN(a,b) ((a)>(b)?(b):(a))
#endif
#ifndef MAX
#define MAX(a,b) ((a)>(b)?(a):(b))
#endif

/* presenter */

struct ffmpeg_video_t {
  AVFormatContext *pFormatCtx;
  int videoStream;
  AVCodecContext *pCodecCtx;
  AVFrame *pFrame;
  AVFrame *pFrameBGRA;
  uint8_t *buffer;
  struct SwsContext *img_convert_ctx;
  AVPacket packet;
  int frame;
  int videoFinished;
};

struct renderer_state_t {
  struct renderer_target_t *targets;
  int nr_targets;
  struct renderer_sequence_t *sequence;
  double start_time;
  struct renderer_log_t *log;
  int timepoint;
  Display *display;
  int screen;
  struct ffmpeg_video_t *video;
  Imlib_Image *framebuffer;
  int width, height;
  struct ffmpeg_video_t *(videos[VIDEO_IDS]);
};

void ffmpeg_close_and_free_video(struct ffmpeg_video_t *video);
void free_commands(struct renderer_commands_t *c) {
  if(c) {
    struct renderer_commands_t *n = c->next;
    switch(c->type) {
    case RC_LOAD_VIDEO:
      ffmpeg_close_and_free_video
        (((struct rc_load_video_t*)c->data)->ffmpeg_video);
      break;
    default:
      break;
    }
    free(c->data);
    free(c);
    free_commands(n);
  }
}

void free_sequence(struct renderer_sequence_t *s) {
  if(s) {
    struct renderer_sequence_t *n = s->next;
    free_commands(s->commands);
    free(s);
    free_sequence(n);
  }
}

void free_renderer_arguments(struct renderer_arguments_t *a) {
  free_sequence(a->sequence);
  free(a->targets);
  free(a);
}

double current_time(void) {
  struct timeval time;
  if (gettimeofday(&time, NULL)!=0) presenter_error("gettimeofday failed");
  return ((double)time.tv_sec)+((double)time.tv_usec)/1e6;
}

/* ffmpeg */

int ffmpeg_first_video_stream(struct ffmpeg_video_t *video) {
  if (av_find_stream_info(video->pFormatCtx)<0) {
    presenter_error("Can't get video stream information");
  }
  for (unsigned int i = 0; i<video->pFormatCtx->nb_streams; i++) {
    if (video->pFormatCtx->streams[i]->codec->codec_type==AVMEDIA_TYPE_VIDEO) {
      return i;
    }
  }
  presenter_error("Can't find first video stream");
}

AVCodecContext *ffmpeg_get_codec(struct ffmpeg_video_t *video) {
  AVCodecContext *pCodecCtx =
    video->pFormatCtx->streams[video->videoStream]->codec;
  AVCodec *pCodec = avcodec_find_decoder(pCodecCtx->codec_id);
  if (pCodec==NULL) presenter_error("Unsupported codec!");
  if (avcodec_open(pCodecCtx, pCodec)<0) presenter_error("Can't open codec!");
  return pCodecCtx;
}

int ffmpeg_next_frame(struct ffmpeg_video_t *video) {
  av_free_packet(&video->packet);
  int frameFinished;
  int nextFrameValid = av_read_frame(video->pFormatCtx, &video->packet)>=0;
  if (nextFrameValid&&video->packet.stream_index==video->videoStream) {
    avcodec_decode_video2(video->pCodecCtx,
                          video->pFrame,
                          &frameFinished,
                          &video->packet);
    if (frameFinished) video->frame++;
    else ffmpeg_next_frame(video);
  } else if (nextFrameValid) {
    ffmpeg_next_frame(video);
  } else if (!video->videoFinished&&!nextFrameValid) {
    /* This is required because ffmpeg hangs on to many frames internally */
    AVPacket packet;
    packet.data = 0;
    packet.size = 0;
    avcodec_decode_video2(video->pCodecCtx,
			  video->pFrame,
			  &frameFinished,
			  &packet);
    if (frameFinished) video->frame++;
    else video->videoFinished = 1;
  }
  return !video->videoFinished;
}

char ffmpeg_video_finished(struct ffmpeg_video_t *video) {
  return video->videoFinished==1;
}

void ffmpeg_close_and_free_video(struct ffmpeg_video_t *video) {
  av_free(video->buffer);
  av_free(video->pFrameBGRA);
  av_free(video->pFrame);
  avcodec_close(video->pCodecCtx);
  av_close_input_file(video->pFormatCtx);
  av_free_packet(&video->packet);
  video->videoFinished = 1;
  free(video);
}

struct ffmpeg_video_t *ffmpeg_open_video(char* filename) {
  struct ffmpeg_video_t *video = malloc(sizeof(struct ffmpeg_video_t));
  bzero(video, sizeof(video));
  av_register_all();
  if (avformat_open_input(&video->pFormatCtx, filename, NULL, NULL)!=0) {
    presenter_error("Can't open video %s", filename);
  }
  video->videoStream = ffmpeg_first_video_stream(video);
  video->pCodecCtx = ffmpeg_get_codec(video);
  video->pFrame = avcodec_alloc_frame();
  video->pFrameBGRA = avcodec_alloc_frame();
  if (!video->pFrameBGRA||!video->pFrame) presenter_error("Can't allocate frame");
  video->buffer =
    (uint8_t *)av_malloc(avpicture_get_size(PIX_FMT_BGRA,
					    video->pCodecCtx->width,
					    video->pCodecCtx->height) *
			 sizeof(uint8_t));
  avpicture_fill((AVPicture *)video->pFrameBGRA, video->buffer, PIX_FMT_BGRA,
		 video->pCodecCtx->width, video->pCodecCtx->height);
  video->img_convert_ctx =
    sws_getContext(video->pCodecCtx->width, video->pCodecCtx->height,
		   video->pCodecCtx->pix_fmt,
		   video->pCodecCtx->width, video->pCodecCtx->height,
		   PIX_FMT_BGRA, SWS_BICUBIC,
		   NULL, NULL, NULL);
  video->videoFinished = 0;
  video->frame = 0;
  av_init_packet(&video->packet);
  ffmpeg_next_frame(video);
  return video;
}

uint8_t *ffmpeg_get_frame(struct ffmpeg_video_t *video) {
  uint8_t *data = malloc(avpicture_get_size(PIX_FMT_BGRA,
                                            video->pCodecCtx->width,
                                            video->pCodecCtx->height) *
                         sizeof(uint8_t));
  sws_scale(video->img_convert_ctx, (const uint8_t * const*)video->pFrame->data,
	    video->pFrame->linesize, 0,
	    video->pCodecCtx->height,
	    video->pFrameBGRA->data, video->pFrameBGRA->linesize);
  memcpy(data, video->buffer,
	 avpicture_get_size(PIX_FMT_BGRA,
			    video->pCodecCtx->width,
			    video->pCodecCtx->height) * sizeof(uint8_t));
  return data;
}

unsigned int ffmpeg_video_width(struct ffmpeg_video_t *video) {
  return video->pCodecCtx->width;
}

unsigned int ffmpeg_video_height(struct ffmpeg_video_t *video) {
  return video->pCodecCtx->height;
}

double ffmpeg_video_frame_rate(struct ffmpeg_video_t *video) {
  /* hints from
     http://ffmpeg.org/pipermail/ffmpeg-cvslog/2011-August/039936.html*/
  int i = video->videoStream;
  int rfps = video->pFormatCtx->streams[i]->r_frame_rate.num;
  int rfps_base = video->pFormatCtx->streams[i]->r_frame_rate.den;
  return (float)rfps / rfps_base;
}

Imlib_Image *ffmpeg_get_frame_as_imlib(struct ffmpeg_video_t *video) {
  sws_scale(video->img_convert_ctx, (const uint8_t * const*)video->pFrame->data,
	    video->pFrame->linesize, 0,
	    video->pCodecCtx->height,
	    video->pFrameBGRA->data, video->pFrameBGRA->linesize);
  Imlib_Image *image =
    imlib_create_image_using_copied_data(video->pCodecCtx->width,
					 video->pCodecCtx->height,
					 (uint32_t*)video->buffer);
  return image;
}

/* This is the unsafe version of the above, you must not advance the
   frame or free the ffmpeg video until you are done with the imlib image.
   It's faster because it doesn't copy the data. */

Imlib_Image *ffmpeg_get_frame_as_imlib_unsafe(struct ffmpeg_video_t *video) {
  sws_scale(video->img_convert_ctx, (const uint8_t * const*)video->pFrame->data,
	    video->pFrame->linesize, 0,
	    video->pCodecCtx->height,
	    video->pFrameBGRA->data, video->pFrameBGRA->linesize);
  Imlib_Image *image =
    imlib_create_image_using_data(video->pCodecCtx->width,
                                  video->pCodecCtx->height,
                                  (uint32_t*)video->buffer);
  return image;
}

/* engine */

/* return #t if we should rerun for another iteration */
int execute_commands(struct renderer_commands_t *commands,
                      struct renderer_state_t *state,
                      int iteration) {
  int command = 0;
  double advance_time = INFINITY;
  int another_iteration = 0;
  while(commands) {
#if DEBUGGING
    printf("command(%d) %d @ %d,%d\n", command, commands->type, volumes, volume);
#endif
    switch(commands->type) {
    case RC_ADVANCE:
      advance_time = ((struct rc_advance_t*)commands->data)->s;
      break;
    case RC_SLEEP: {
      double sleep_time = ((struct rc_sleep_t*)commands->data)->s;
      while(current_time()-state->log[state->timepoint].start_timestamp
            /* a bit of slack time, if we make this exact we'll
               overshoot at the end of the function */
            < (MIN(sleep_time,advance_time)-0.01)) {
        usleep(10); // 0.01ms
      }
    }
      break;
    case RC_FILL_RECTANGLE: {
      struct rc_fill_rectangle_t *t = ((struct rc_fill_rectangle_t*)commands->data);
      imlib_context_set_image(state->framebuffer);
      imlib_context_set_color(t->r,t->g,t->b,t->a);
      imlib_image_fill_rectangle((int)(t->x*state->width), (int)(t->y*state->height),
                                 (int)(t->width*state->width), (int)(t->height*state->height));
    }
      break;
    case RC_IMAGE: {
      struct rc_image_t *i = ((struct rc_image_t*)commands->data);
      imlib_context_set_image(i->image);
      int width = imlib_image_get_width(), height = imlib_image_get_height();
      imlib_context_set_image(state->framebuffer);
      imlib_blend_image_onto_image(i->image, 0, 0, 0, width, height,
                                   (int)(i->x*state->width), (int)(i->y*state->height),
                                   (int)(i->width*state->width), (int)(i->height*state->height));
    }
      break;
    case RC_TEXT: {
      struct rc_text_t *t = ((struct rc_text_t*)commands->data);
      Imlib_Font font;
      if(!(font = imlib_load_font(t->font)))
        presenter_error("(%d,%d) can't load requested font %s", state->timepoint, command,
                        t->font);
      imlib_context_set_font(font);
      imlib_context_set_color(t->r,t->g,t->b,t->a);
      imlib_context_set_direction(t->direction);
      imlib_context_set_angle(t->angle);
      imlib_text_draw((int)(t->x*state->width), (int)(t->y*state->height), t->text);
      imlib_free_font();
    }
      break;
    case RC_RENDER: {
      for(int i = 0; i < state->nr_targets; ++i) {
        struct renderer_target_t target = state->targets[i];
        imlib_context_set_image(state->framebuffer);
        Imlib_Image image;
        if(target.width != state->width || target.height != state->height) {
          image = imlib_create_cropped_scaled_image(0, 0,
                                                    state->width, state->height,
                                                    target.width, target.height);
        }
        else image = state->framebuffer;
        imlib_context_set_image(image);
        imlib_context_set_drawable(target.window);
        imlib_render_image_on_drawable(target.x, target.y);
        if(target.width != state->width || target.height != state->height)
          imlib_free_image_and_decache();
      }
      XFlush(state->display);
    }
      break;
    case RC_WAKE_GUI: {
      struct rc_wake_gui_t *t = ((struct rc_wake_gui_t*)commands->data);
      XEvent event;
      event.type = KeyPress;
      event.xkey.keycode = 9;
      event.xkey.state = 0;
      XSendEvent(state->display, t->window, 0, 0, &event);
      XFlush(state->display);
    }
      break;
    case RC_LOAD_VIDEO: {
      struct rc_load_video_t *l = ((struct rc_load_video_t*)commands->data);
      state->videos[l->id] = l->ffmpeg_video;
    }
      break;
    case RC_SHOW_VIDEO_FRAME: {
      struct rc_show_video_frame_t *s = ((struct rc_show_video_frame_t*)commands->data);
      Imlib_Image image = ffmpeg_get_frame_as_imlib_unsafe(state->videos[s->id]);
      imlib_context_set_image(image);
      int width = imlib_image_get_width(), height = imlib_image_get_height();
      imlib_context_set_image(state->framebuffer);
      imlib_blend_image_onto_image(image, 0, 0, 0, width, height,
                                   (int)(s->x*state->width), (int)(s->y*state->height),
                                   (int)(s->width*state->width), (int)(s->height*state->height));
      imlib_context_set_image(image);
      /* this is almost free because it only frees the surrounding
         structure not the image as that's still property of ffmpeg */
      imlib_free_image_and_decache();
    }
      break;
    case RC_ADVANCE_VIDEO_FRAME: {
      struct rc_advance_video_frame_t *a = ((struct rc_advance_video_frame_t*)commands->data);
      ffmpeg_next_frame(state->videos[a->id]);
    }
      break;
    case RC_LOOP: {
      struct rc_loop_t *l = ((struct rc_loop_t*)commands->data);
      another_iteration = another_iteration || (l->iterations > iteration);
    }
      break;
    case RC_START_VOLUME: {
      volume = 0;
    }
      break;
    case RC_WAIT_FOR_VOLUME: {
      while(!volume) {
        usleep(10); // 0.01ms
      }
      volume = 0;
    }
      break;
    case RC_STOP_ON_VOLUME_WITHOUT_CLEARING: {
      if(volume) {
        /* stop iteration and move on */
        return 0;
      }
    }
      break;
    case RC_STOP_ON_VOLUME_AND_CLEAR: {
      if(volume) {
        volume = 0;
        /* stop iteration and move on */
        return 0;
      }
    }
      break;
    default:
      presenter_error("(%d,%d) unknown or unimplemented command %d %p\n",
                      state->timepoint, command, commands->type, commands->data);
      break;
    }
    ++command;
    commands = commands->next;
  }
  double time = current_time();
  if(time > advance_time + state->log[state->timepoint].start_timestamp) {
    /* TODO make this a flag, not needed for 9events */
#if 0
    presenter_error("(%d,%d) can't keep up, had %lf s but took %lf s",
                    state->timepoint,
                    command,
                    advance_time,
                    time - state->log[state->timepoint].start_timestamp);
#endif
    printf("(%d,%d) can't keep up, had %lf s but took %lf s",
                    state->timepoint,
                    command,
                    advance_time,
                    time - state->log[state->timepoint].start_timestamp);
  } else {
#if DEBUGGING
    printf("(%d,%d) %lf s and took %lf s\n",
           state->timepoint,
           command,
           advance_time,
           time - state->log[state->timepoint].start_timestamp);
    max_time = MAX(max_time, time - state->log[state->timepoint].start_timestamp);
#endif
  }
  return another_iteration;
}

/* task */

void* renderer(void *args_) {
#if DEBUGGING
  printf("starting renderer\n");
#endif
  struct renderer_arguments_t *args = args_;
  struct renderer_state_t state;
  state.targets = args->targets;
  state.nr_targets = args->nr_targets;
  state.sequence = args->sequence;
  state.log = malloc(args->sequence_length * sizeof(struct renderer_log_t));
  state.display = XOpenDisplay("");
  state.screen = DefaultScreen(state.display);
  state.video = NULL;
  state.framebuffer = imlib_create_image(args->targets[0].width,
                                         args->targets[0].height);
  state.width = args->targets[0].width;
  state.height = args->targets[0].height;
  for(int i = 0; i < VIDEO_IDS; ++i)
    state.videos[i] = NULL;

  imlib_context_disconnect_display();
  imlib_context_set_display(state.display);
  imlib_context_set_visual(XDefaultVisual(state.display, state.screen));
  imlib_context_set_colormap(XDefaultColormap(state.display, state.screen));

  /* 100MB of imlib font cache, just to make sure there's no lag */
  imlib_set_font_cache_size(100*1024*1024);

  struct renderer_result_t *result = malloc(sizeof(struct renderer_result_t));
  result->log = state.log;

  volume = 0;
  volumes = 0;
  counter = 0;
  first_trigger = 0;

  /* wait for the trigger */
  printf("waiting for trigger\n");
  while(!first_trigger) usleep(100);

  state.timepoint = 0;
  int timepoint_iteration = 0;
  while(1) {
    if(renderer_stopped) {
      result->stop_reason = RENDERER_WAS_STOPPED;
      result->log = state.log;
      result->timepoints_processed = state.timepoint;
      break;
    }
    if(!state.sequence) {
      result->stop_reason = RENDERER_FINISHED_SEQUENCE;
      result->log = state.log;
      result->timepoints_processed = state.timepoint;
      break;
    }
    state.log[state.timepoint].start_timestamp = current_time();
    state.log[state.timepoint].volume = volumes;
    if(execute_commands(state.sequence->commands, &state, timepoint_iteration)) {
      timepoint_iteration++;
    } else {
      timepoint_iteration = 0;
      state.sequence = state.sequence->next;
    }
    state.timepoint++;
  }

  renderer_stopped = 1;

  XEvent event;
  event.type = KeyPress;
  event.xkey.keycode = 9;
  event.xkey.state = 0;
  XSendEvent(state.display, args->wakeup_target, 0, 0, &event);
  XFlush(state.display);
#if DEBUGGING
  printf("stopping renderer, longest iteration %lf\n", max_time);
#endif
  return (void*)result;
}
