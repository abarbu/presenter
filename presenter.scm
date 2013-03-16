(use chicken)
(use extras srfi-1 traversal bind easyffi lolevel matchable define-structure
     linear-algebra imlib2 qobischeme-ui scheme2c-compatibility
     random-bsd xlib format)

#>
#include "X11/Xlib.h"
#include "Imlib2.h"
#include "stdlib.h"
<#

(bind-rename/pattern "_" "-")

(bind-options mutable-fields: #t)

;; #include "presenterlib-c.h"

(bind* "#include \"presenterlib-c.h\"")

;; Two windows, a regular define-application and a window for displaying to the subject
;; The latter has no buttons, clickability, or anything similar
;; A preview in the main window shows you what the subjects are seeing

(define *viewer-width* 800)
(define *viewer-height* 600)
(define *viewer-x* 0)
(define *viewer-y* 0)
(define *viewer-window* #f)

(define *preview-viewer-width* 800)
(define *preview-viewer-height* 600)
(define *preview-viewer-x* 0)
(define *preview-viewer-y* 0)
(define *preview-viewer-window* #f)

(define *disable-preview* #f)

;; defining sequences

(define *sequence-name* 'image-classes)
(define *sequence* #f)

(define *renderer-running?* #f)

(define *runs-sequence* '())
(define *run* 1)

(define (standard-timepoint time . contents)
 `(,(make-rc-advance time)
   ,@contents
   ,(make-rc-render #f)
   ,(make-rc-sleep time)))

(define (tr-timepoint time . contents)
 `(,@contents
   ,(make-rc-render #f)
   ,(make-rc-wait-for-volume #f)))

(define-structure rc-advance s)
(define-structure rc-sleep s)
(define-structure rc-fill-rectangle x y width height rgba)
(define-structure rc-image filename x y width height)
(define-structure rc-text text font rgba direction angle x y)
(define-structure rc-render dummy)
(define-structure rc-wake-gui dummy)
(define-structure rc-load-video filename id)
(define-structure rc-show-video-frame id x y width height a)
(define-structure rc-advance-video-frame id)
(define-structure rc-loop iterations)
(define-structure rc-start-volume dummy)
(define-structure rc-wait-for-volume dummy)
(define-structure rc-stop-on-volume-without-clearing dummy)
(define-structure rc-stop-on-volume-and-clear dummy)

(define (concat l) (qreduce append l '()))

(define (random-member l) (list-ref l (random-integer (length l))))

(define (number->padded-string-of-length n l)
 (format #f (format #f "~~~a,48d" l) n))

(define (generate-sequence-of-images time-per-image time-for-fixation)
 (cons
  (standard-timepoint
   10
   (make-rc-fill-rectangle 0 0 1 1 '#(255 255 255 255))
   (make-rc-text "X" "DejaVuSans/50" '#(0 0 0 255)
                 0
                 0
                 0.45 0.4))
  (concat
   (map-n
     (lambda (a)
      (list (standard-timepoint
             time-per-image
             (make-rc-image
              (let ((class (random-member
                            '(("252.car-side-101" "252")
                              ("251.airplanes-101" "251")
                              ("072.fire-truck" "072")
                              ("224.touring-bike" "224")
                              ("125.knife" "125")
                              ("180.screwdriver" "180")
                              ("092.grapes" "092")
                              ("221.tomato" "221")
                              ("196.spaghetti" "196")))))
               (string-append (getenv "HOME")
                              "/datasets/"
                              (first class)
                              "/"
                              (second class)
                              "_"
                              (number->padded-string-of-length
                               (+ (random-integer 30) 1)
                               4)
                              ".jpg"))
              0 0 1 1))
            (standard-timepoint
             time-for-fixation
             (make-rc-fill-rectangle 0 0 1 1 '#(255 255 255 255))
             (make-rc-text "X" "DejaVuSans/50" '#(0 0 0 255)
                           0
                           0
                           0.45 0.4))))
    46))))

(define *example-sequence*
 (list
  (standard-timepoint
   0.3
   (make-rc-fill-rectangle 0 0 1 1 '#(255 0 0 255)))
  (standard-timepoint
   0.3
   (make-rc-image "/home/andrei/p1.png" 0 0 1 1))
  (standard-timepoint
   0.3
   (make-rc-fill-rectangle 0 0 1 1 '#(0 0 255 128))
   (make-rc-text "Hello world" "DejaVuSans/20" '#(0 255 0 255)
		 (c-value int "IMLIB_TEXT_TO_RIGHT")
		 0
		 0.5 0.5)
   (make-rc-wake-gui #f))
  (standard-timepoint
   0.3
   (make-rc-fill-rectangle 0 0 1 1 '#(255 0 255 255)))))

(define *video-example-sequence*
 (list
  (standard-timepoint
   0.05
   (make-rc-load-video "somevideo.avi" 0)
   (make-rc-show-video-frame 0 0 0 1 1 255)
   (make-rc-advance-video-frame 0))
  (standard-timepoint
   0.05
   (make-rc-show-video-frame 0 0 0 1 1 255)
   (make-rc-advance-video-frame 0))
  (standard-timepoint
   0.05
   (make-rc-show-video-frame 0 0 0 1 1 255)
   (make-rc-advance-video-frame 0))
  (standard-timepoint
   0.05
   (make-rc-show-video-frame 0 0 0 1 1 255)
   (make-rc-advance-video-frame 0)
   (make-rc-loop 20))))

(define *image-classes-sequence* (generate-sequence-of-images 4 6))

(define *y2-sequence*
 (concat
  (map
   (lambda (a)
    (list (standard-timepoint
           (/ 24)
           (make-rc-load-video (string-append (getenv "HOME") "/datasets/videos/" (car a)) 0)
           (make-rc-show-video-frame 0 0 0 1 1 255)
           (make-rc-advance-video-frame 0))
          (standard-timepoint
           (/ 24)
           (make-rc-show-video-frame 0 0 0 1 1 255)
           (make-rc-advance-video-frame 0)
           (make-rc-loop (- (cdr a) 3)))))
   '(("downsampled-STOPS_20120306_SH1_02_C4-003023-003524.avi" . 202)
     ("downsampled-STOPS_20120306_SH1_02_C4-003660-003747.avi" . 36)
     ("downsampled-STOPS_20120306_SH1_02_C4-004034-004177.avi" . 58)
     ("downsampled-STOPS_20120306_SH1_02_C4-004387-004510.avi" . 50)
     ("downsampled-STOPS_20120306_SH1_02_C4-004870-005235.avi" . 147)
     ("downsampled-STOPS_20120306_SH1_02_C4-006511-006670.avi" . 65)
     ("downsampled-STOPS_20120306_SH1_02_C4-007545-007946.avi" . 161)
     ("downsampled-STOPS_20120306_SH1_02_C4-008836-009395.avi" . 225)
     ("downsampled-STOPS_20120306_SH1_02_C4-012238-012304.avi" . 27)
     ("downsampled-STOPS_20120306_SH1_02_C4-012238-014011.avi" . 711)
     ("downsampled-STOPS_20120306_SH1_02_C4-012337-014011.avi" . 671)
     ("downsampled-STOPS_20120306_SH1_02_C4-014865-015354.avi" . 197)
     ("downsampled-STOPS_20120306_SH1_02_C4-017768-018049.avi" . 113)
     ("downsampled-STOPS_20120306_SH1_02_C4-018491-019732.avi" . 498)
     ("downsampled-STOPS_20120306_SH1_02_C4-020022-020320.avi" . 120)
     ("downsampled-STOPS_20120306_SH1_02_C4-020409-020687.avi" . 112)
     ("downsampled-STOPS_20120306_SH1_02_C4-024068-025367.avi" . 521)
     ("downsampled-STOPS_20120306_SH1_02_C4-028150-029283.avi" . 455)
     ("downsampled-STOPS_20120306_SH1_02_C4-032207-032317.avi" . 45)
     ("downsampled-STOPS_20120306_SH1_02_C4-032207-032505.avi" . 120)
     ("downsampled-STOPS_20120306_SH1_03_C1-001766-003013.avi" . 500)
     ("downsampled-STOPS_20120306_SH1_03_C1-002520-003839.avi" . 529)
     ("downsampled-STOPS_20120306_SH1_03_C1-003900-005743.avi" . 739)
     ("downsampled-STOPS_20120306_SH1_03_C1-006300-008299.avi" . 801)
     ("downsampled-STOPS_20120306_SH1_03_C1-022080-028782.avi" . 2684)
     ("downsampled-STOPS_20120306_SH1_03_C1-028848-034738.avi" . 2359)))))

(define *new3-sequence*
 (concat
  (map
   (lambda (videoname)
    (list (standard-timepoint
	   (/ 3)
	   (make-rc-load-video (format #f "~a/datasets/~a" (getenv "HOME") (caar videoname)) 0)
	   (make-rc-show-video-frame 0 0 0 1 1 255)
	   (make-rc-advance-video-frame 0))
	  (standard-timepoint
	   (/ 3)			; 3 fps
	   (make-rc-show-video-frame 0 0 0 1 1 255)
	   (make-rc-advance-video-frame 0)
	   (make-rc-loop 10))		; max of 12 frames
	  (standard-timepoint
	   7
	   (make-rc-fill-rectangle 0 0 1 1 '#(255 255 255 255))
           (make-rc-text "X" "DejaVuSans/50" '#(0 0 0 255)
                         0
                         0
                         0.45 0.4))))
   '((("videos/MVI_0820.mov" 12) APPROACHED)
     (("videos/MVI_0837.mov" 12) CARRIED)
     (("videos/MVI_0860.mov" 12) PUT)
     (("videos/MVI_0872.mov" 12) PICKED)
     (("videos/MVI_0822.mov" 12) APPROACHED)
     (("videos/MVI_0884.mov" 12) CARRIED)
     (("videos/MVI_0862.mov" 12) PUT)
     (("videos/MVI_0878.mov" 12) PICKED)
     (("videos/MVI_0853.mov" 12) APPROACHED)
     (("videos/MVI_0899.mov" 12) CARRIED)
     (("videos/MVI_0866.mov" 12) PUT)
     (("videos/MVI_0911.mov" 12) PICKED)
     (("videos/MVI_0858.mov" 12) APPROACHED)
     (("videos/MVI_0900.mov" 12) CARRIED)
     (("videos/MVI_0892.mov" 12) PUT)
     (("videos/MVI_0838.mov" 13) PICKED)
     (("videos/MVI_0886.mov" 12) APPROACHED)
     (("videos/MVI_0915.mov" 12) CARRIED)
     (("videos/MVI_0828.mov" 13) PUT)
     (("videos/MVI_0845.mov" 13) PICKED)
     (("videos/MVI_0855.mov" 13) APPROACHED)
     (("videos/MVI_0835.mov" 14) CARRIED)
     (("videos/MVI_0834.mov" 13) PUT)
     (("videos/MVI_0875.mov" 13) PICKED)))))

;; misc

(define (string->c-string str f)
 (let ((buf (allocate (+ (string-length str) 1))))
  (for-each-indexed
   (lambda (c i) (c-byte-set! buf i (char->integer c)))
   (string->list str))
  (c-byte-set! buf (string-length str) 0)
  buf))

;; current presenter run

(define *sequence-arguments* #f)

;; image cache

(define-structure image-cache images)   ; ((filename . imlib-image))
(define *sequence-image-cache* (make-image-cache '()))

(define (free-image-cache sequence-image-cache)
 (for-each (lambda (cache)
            ((c-function void ("imlib_context_set_image" c-pointer)) (cdr cache))
            ((c-function void ("imlib_free_image"))))
  (image-cache-images sequence-image-cache))
 (set-image-cache-images! sequence-image-cache '()))

(define (load-image-with-cache! filename cache)
 (let ((image (assoc filename (image-cache-images cache))))
  (if image
      (cdr image)
      (begin
       (let ((image ((c-function c-pointer ("imlib_load_image_immediately" c-string))
                     filename)))
        (unless image (error "Failed to load" filename))
        (set-image-cache-images! cache
                                 (cons (cons filename image)
                                       (image-cache-images cache)))
        image)))))

;; interface to C

(define start-renderer (c-function void ("start_renderer" c-pointer)))
(define stop-renderer (c-function c-pointer ("stop_renderer")))

(define *renderer-arguments* #f)

(define (command->c-type command)
 (cond ((rc-render? command) (c-value int "RC_RENDER"))
       ((rc-stop-on-volume-without-clearing? command)
        (c-value int "RC_STOP_ON_VOLUME_WITHOUT_CLEARING"))
       ((rc-stop-on-volume-and-clear? command)
        (c-value int "RC_STOP_ON_VOLUME_AND_CLEAR"))
       ((rc-advance? command) (c-value int "RC_ADVANCE"))
       ((rc-sleep? command) (c-value int "RC_SLEEP"))
       ((rc-fill-rectangle? command) (c-value int "RC_FILL_RECTANGLE"))
       ((rc-image? command) (c-value int "RC_IMAGE"))
       ((rc-text? command) (c-value int "RC_TEXT"))
       ((rc-wake-gui? command) (c-value int "RC_WAKE_GUI"))
       ((rc-load-video? command) (c-value int "RC_LOAD_VIDEO"))
       ((rc-show-video-frame? command) (c-value int "RC_SHOW_VIDEO_FRAME"))
       ((rc-advance-video-frame? command) (c-value int "RC_ADVANCE_VIDEO_FRAME"))
       ((rc-loop? command) (c-value int "RC_LOOP"))
       ((rc-start-volume? command) (c-value int "RC_START_VOLUME"))
       ((rc-wait-for-volume? command) (c-value int "RC_WAIT_FOR_VOLUME"))
       (else (error "unknown/unimplemented command" command))))

;; You cannot call command->c-data, commands->c, or sequence->c
;; outside of the UI! And not before it has created the viewer and
;; preview windows. They are required for certain commands.

(define (command->c-data command image-cache)
 (cond ((or (rc-render? command)
            (rc-start-volume? command)
            (rc-wait-for-volume? command)
            (rc-stop-on-volume-without-clearing? command)
            (rc-stop-on-volume-and-clear? command))
        (address->pointer 0))
       ((rc-advance? command)
        (let ((a (allocate (c-sizeof "struct rc_advance_t"))))
         ((setter rc-advance-t-s) a (rc-advance-s command))
         a))
       ((rc-sleep? command)
        (let ((a (allocate (c-sizeof "struct rc_sleep_t"))))
         ((setter rc-sleep-t-s) a (rc-sleep-s command))
         a))
       ((rc-fill-rectangle? command)
        (let ((a (allocate (c-sizeof "struct rc_fill_rectangle_t"))))
         ((setter rc-fill-rectangle-t-x) a (rc-fill-rectangle-x command))
         ((setter rc-fill-rectangle-t-y) a (rc-fill-rectangle-y command))
         ((setter rc-fill-rectangle-t-width) a (rc-fill-rectangle-width command))
         ((setter rc-fill-rectangle-t-height) a (rc-fill-rectangle-height command))
         ((setter rc-fill-rectangle-t-r) a (vector-ref (rc-fill-rectangle-rgba command) 0))
         ((setter rc-fill-rectangle-t-g) a (vector-ref (rc-fill-rectangle-rgba command) 1))
         ((setter rc-fill-rectangle-t-b) a (vector-ref (rc-fill-rectangle-rgba command) 2))
         ((setter rc-fill-rectangle-t-a) a (vector-ref (rc-fill-rectangle-rgba command) 3))
         a))
       ((rc-image? command)
        (let ((a (allocate (c-sizeof "struct rc_image_t"))))
         ((setter rc-image-t-x) a (rc-image-x command))
         ((setter rc-image-t-y) a (rc-image-y command))
         ((setter rc-image-t-width) a (rc-image-width command))
         ((setter rc-image-t-height) a (rc-image-height command))
         ((setter rc-image-t-image) a
          (load-image-with-cache! (rc-image-filename command) image-cache))
         a))
       ((rc-text? command)
        (let ((a (allocate (c-sizeof "struct rc_text_t"))))
         ((setter rc-text-t-text) a (rc-text-text command))
         ((setter rc-text-t-font) a (rc-text-font command))
         ((setter rc-text-t-r) a (vector-ref (rc-text-rgba command) 0))
         ((setter rc-text-t-g) a (vector-ref (rc-text-rgba command) 1))
         ((setter rc-text-t-b) a (vector-ref (rc-text-rgba command) 2))
         ((setter rc-text-t-a) a (vector-ref (rc-text-rgba command) 3))
         ((setter rc-text-t-direction) a (rc-text-direction command))
         ((setter rc-text-t-angle) a (rc-text-angle command))
         ((setter rc-text-t-x) a (rc-text-x command))
         ((setter rc-text-t-y) a (rc-text-y command))
         a))
       ((rc-wake-gui? command)
        (let ((a (allocate (c-sizeof "struct rc_wake_gui_t"))))
         ((setter rc-wake-gui-t-window) a *display-pane*)
         a))
       ((rc-load-video? command)
        (let ((a (allocate (c-sizeof "struct rc_load_video_t")))
              (ffmpeg-video
               ((c-function c-pointer ("ffmpeg_open_video" c-string))
                (rc-load-video-filename command))))
         ((setter rc-load-video-t-ffmpeg-video) a ffmpeg-video)
         ((setter rc-load-video-t-id) a (rc-load-video-id command))
         a))
       ((rc-show-video-frame? command)
        (let ((a (allocate (c-sizeof "struct rc_show_video_frame_t"))))
         ((setter rc-show-video-frame-t-x) a (rc-show-video-frame-x command))
         ((setter rc-show-video-frame-t-y) a (rc-show-video-frame-y command))
         ((setter rc-show-video-frame-t-width) a (rc-show-video-frame-width command))
         ((setter rc-show-video-frame-t-height) a (rc-show-video-frame-height command))
         ((setter rc-show-video-frame-t-a) a (rc-show-video-frame-a command))
         ((setter rc-show-video-frame-t-id) a (rc-show-video-frame-id command))
         a))
       ((rc-advance-video-frame? command)
        (let ((a (allocate (c-sizeof "struct rc_advance_video_frame_t"))))
         ((setter rc-advance-video-frame-t-id) a (rc-advance-video-frame-id command))
         a))
       ((rc-loop? command)
        (let ((a (allocate (c-sizeof "struct rc_loop_t"))))
         ((setter rc-loop-t-iterations) a (rc-loop-iterations command))
         a))
       (else (error "unknown/unimplemented command" command))))

(define (commands->c commands image-cache)
 (foldr
  (lambda (command prev)
   (let ((c (allocate (c-sizeof "struct renderer_commands_t"))))
    ((setter renderer-commands-t-type) c (command->c-type command))
    ((setter renderer-commands-t-data) c
     (command->c-data command image-cache))
    ((setter renderer-commands-t-next) c prev)
    c))
  (address->pointer 0)
  commands))

(define (sequence->c sequence image-cache)
 (foldr
  (lambda (commands prev)
   (let ((s (allocate (c-sizeof "struct renderer_sequence_t"))))
    ((setter renderer-sequence-t-commands) s (commands->c commands image-cache))
    ((setter renderer-sequence-t-next) s prev)
    s))
  (address->pointer 0)
  sequence))

(define (sequence-length sequence)
 (foldl (lambda (s commands)
         (+ s
            1
            (foldl + 0 (map rc-loop-iterations
                            (remove-if-not rc-loop? commands)))))
        0
        sequence))

(define (renderer-arguments->c sequence image-cache)
 (let ((a (allocate (c-sizeof "struct renderer_arguments_t"))))
  ((setter renderer-arguments-t-sequence) a
   (sequence->c sequence image-cache))
  ((setter renderer-arguments-t-sequence-length) a (sequence-length sequence))
  ((setter renderer-arguments-t-wakeup-target) a *display-pane*)
  (let ((ts (allocate (* 2 (c-sizeof "struct renderer_target_t")))))
   ((setter renderer-target-t-window) ts *viewer-window*)
   ((setter renderer-target-t-width) ts *viewer-width*)
   ((setter renderer-target-t-height) ts *viewer-height*)
   ((setter renderer-target-t-x) ts 0)
   ((setter renderer-target-t-y) ts 0)
   (if *disable-preview*
       ((setter renderer-arguments-t-nr-targets) a 1)
       (begin 
        ((setter renderer-target-t-window)(pointer+ ts (c-sizeof "struct renderer_target_t"))
         *preview-viewer-window*)
        ((setter renderer-target-t-width)(pointer+ ts (c-sizeof "struct renderer_target_t"))
         *preview-viewer-width*)
        ((setter renderer-target-t-height)(pointer+ ts (c-sizeof "struct renderer_target_t"))
         *preview-viewer-height*)
        ((setter renderer-target-t-x)(pointer+ ts (c-sizeof "struct renderer_target_t")) 0)
        ((setter renderer-target-t-y)(pointer+ ts (c-sizeof "struct renderer_target_t")) 0)
        ((setter renderer-arguments-t-nr-targets) a 2)))
   ((setter renderer-arguments-t-targets) a ts))
  a))

(define (free-renderer-arguments sequence)
 ((c-function void ("free_renderer_arguments" c-pointer)) sequence))

(define (free-renderer sequence image-cache)
 (free-renderer-arguments sequence)
 (free-image-cache image-cache))

(define-structure renderer-result
 ;; finished-sequence or was-stopped
 stop-reason
 timepoints-processed
 log)

(define-structure log start-timestamp volume)

(define (c-log->scheme&free size log)
 (let ((l (map-n (lambda (offset)
                  (let ((ptr (pointer+ log (* offset (c-sizeof "struct renderer_log_t")))))
                   (make-log (renderer-log-t-start-timestamp ptr)
                             (renderer-log-t-volume ptr))))
           size)))
  (free log)
  l))

(define (c-result->scheme&free result sequence-arguments image-cache)
 (let* ((timepoints (renderer-result-t-timepoints-processed result))
        (log (c-log->scheme&free timepoints (renderer-result-t-log result)))
        (reason (renderer-result-t-stop-reason result)))
  (free-renderer sequence-arguments image-cache)
  (free result)
  (make-renderer-result
   (cond ((equal? reason  (c-value int "RENDERER_FINISHED_SEQUENCE"))
          'finished-sequence)
         ((equal? reason (c-value int "RENDERER_WAS_STOPPED"))
          'was-stopped)
         (else (error "unknown result" reason)))
   timepoints
   log)))

(define (define-spinner-buttons c r name f-up f-down f-print)
 (define-button c r (string-append "-  " name) #f
  (lambda () (message "")
          (f-down)
          (redraw-buttons)))
 (define-button (+ c 1) r (lambda () (string-append (f-print) "  +")) #f
  (lambda () (message "")
          (f-up)
          (redraw-buttons))))

(define-application gui 1000 600 5 1 7
 (lambda ()
  (define-button 0 0 "Help" #f help-command)
  (define-button 1 0 "Start" #f
   (lambda ()
    (when *renderer-running?* (message "already running") (abort-gui))
    (set! *sequence*
          (cdr (assoc *sequence-name*
                      `((image-classes . ,*image-classes-sequence*)
                        (y2 . ,*y2-sequence*)
                        (new3 . ,*new3-sequence*)
                        (run . ,(if (null? *runs-sequence*)
                                    '()
                                    (list-ref *runs-sequence* (- *run* 1))))))))
    (message (format #f "setting up sequence '~a' ~a" *sequence-name* *run*))
    (set! *renderer-running?* #t)
    (set! *sequence-arguments* (renderer-arguments->c *sequence*
                                                      *sequence-image-cache*))
    (message (format #f "starting sequence '~a'" *sequence-name*))
    (start-renderer *sequence-arguments*)))
  (define-button 2 0 "Stop" #f
   (lambda ()
    (message "stopped renderer")
    (unless *renderer-running?* (message "renderer isn't running") (abort-gui))
    (set! *renderer-running?* #f)
    (let ((log (c-result->scheme&free (stop-renderer) *sequence-arguments*
                                      *sequence-image-cache*)))
     (pp log) (newline)
     (write-object-to-file
      log
      (format #f "~a-~a-~a.log"
              *run*
              (car (system-output "date +%s"))
              (random-integer 1000))))))
  (define-cycle-button 3 0 *sequence-name*
   (lambda () (say (format #f "sequence ~a" *sequence-name*)))
   (y2 "y2")
   (image-classes "image-classes")
   (new3 "new3")
   (run "run"))
  (define-spinner-buttons 4 0 "run "
   (lambda ()
    (unless (>= (length *runs-sequence*) (+ *run* 1) 0)
     (message "Out of range")(abort-gui))
    (set! *run* (+ *run* 1))
    (message "")
    (redraw-buttons))
   (lambda ()
    (unless (>= (length *runs-sequence*) (- *run* 1)  0)
     (message "Out of range")(abort-gui))
    (set! *run* (- *run* 1))
    (message "")
    (redraw-buttons))
   (lambda () (format #f "~a" *run*)))
  (define-button 6 0 "Quit" #f quit)
  (define-key (list (control #\x) (control #\c)) "Quit" quit)
  (define-key (control #\h) "Help" help-command)
  (set! *viewer-window*
        (xcreatesimplewindow
         *display* *root-window*
         *viewer-x* *viewer-y*
         *viewer-width* *viewer-height*
         1
         (xcolor-pixel (second *foreground*))
         (xcolor-pixel (second *background*))))
  (let ((hints (make-xsizehints)))
   (set-xsizehints-x! hints *viewer-x*)
   (set-xsizehints-y! hints *viewer-y*)
   (set-xsizehints-min_width! hints *viewer-width*)
   (set-xsizehints-max_width! hints *viewer-width*)
   (set-xsizehints-min_height! hints *viewer-height*)
   (set-xsizehints-max_height! hints *viewer-height*)
   (set-xsizehints-flags! hints (+ USPOSITION PPOSITION PMINSIZE PMAXSIZE))
   (xsetwmnormalhints *display* *viewer-window* hints))
  (xmapraised *display* *viewer-window*)
  (set! *preview-viewer-window*
        (xcreatesimplewindow
         *display* *display-pane*
         *preview-viewer-x* *preview-viewer-y*
         *preview-viewer-width* *preview-viewer-height*
         1
         (xcolor-pixel (second *foreground*))
         (xcolor-pixel (second *background*))))
  (xmapraised *display* *preview-viewer-window*))
 (lambda () #f)
 (lambda ()
  (xdestroywindow *display* *viewer-window*)
  (xdestroywindow *display* *preview-viewer-window*))
 (lambda ()
  (when (and (= (c-value int "renderer_stopped") 1)
             *renderer-running?*)
   (message "renderer finished")
   (set! *renderer-running?* #f)
   (let ((log (c-result->scheme&free (stop-renderer) *sequence-arguments*
                                     *sequence-image-cache*)))
    (pp log) (newline)
    (write-object-to-file
     log
     (format #f "~a-~a-~a.log"
             *run*
             (car (system-output "date +%s"))
             (random-integer 1000)))))))

(define (system-output cmd)
 (with-temporary-file "/tmp/system.out"
		      (lambda (file)
		       (system (format #f "~a > ~s" cmd file))
		       (read-text-file file))))

(define imlib-add-path-to-font-path
 (c-function void ("imlib_add_path_to_font_path" c-string)))

(define (read-object-from-file1 pathname)
 (if (string=? pathname "-") (read) (call-with-input-file pathname read)))

(define (fixation-to-tr seconds/tr)
 (tr-timepoint
  seconds/tr
  (make-rc-fill-rectangle 0 0 1 1 '#(0 0 0 255))
  (make-rc-fill-rectangle 0.47 0.495 0.06 0.01 '#(255 255 255 255))
  (make-rc-fill-rectangle 0.495 0.46 0.01 0.08 '#(255 255 255 255))))

(define (fixation-time seconds/tr)
 (standard-timepoint
  seconds/tr
  (make-rc-fill-rectangle 0 0 1 1 '#(0 0 0 255))
  (make-rc-fill-rectangle 0.47 0.495 0.06 0.01 '#(255 255 255 255))
  (make-rc-fill-rectangle 0.495 0.46 0.01 0.08 '#(255 255 255 255))))

(define-command (main
		 (at-most-one ("window-position"
			       window-position?
			       (window-x "x" integer-argument 0)
			       (window-y "y" integer-argument 0)))
                 (at-most-one ("viewer-position"
			       viewer-position?
			       (viewer-x "x" integer-argument 0)
			       (viewer-y "y" integer-argument 0)))
                 (at-most-one ("disable-preview" disable-preview?))
                 (at-most-one ("viewer-size"
			       viewer-size?
			       (viewer-width "width" integer-argument 0)
			       (viewer-height "height" integer-argument 0)))
                 (at-most-one ("runs-directory"
			       runs-directory?
			       (runs-directory "configuration-directory" string-argument "")
                               (stimuli-directory "stimuli-directory" string-argument "")
                               (fps "fps" integer-argument 0)
                               (frames "frames" integer-argument 0)))
                 (at-most-one ("tr" tr?
                               (slices/tr "slices" integer-argument 0)
                               (seconds/tr "seconds" real-argument 0))))
 (set! *disable-preview* disable-preview?)
 (when viewer-position?
  (set! *viewer-x* viewer-x)
  (set! *viewer-y* viewer-y))
 (when viewer-size?
  (set! *viewer-width* viewer-width)
  (set! *viewer-height* viewer-height))
 (when window-position?
  (set! *window-position?* #t)
  (set! *window-position-x* window-x)
  (set! *window-position-y* window-y))
 (when runs-directory?
  (set! *runs-sequence*
        (map (lambda (d)
              (concat
               (map
                (lambda (e)
                 (cond ((equal? e 'FIXATION)
                        (list
                         (tr-timepoint
                          seconds/tr
                          (make-rc-fill-rectangle 0 0 1 1 '#(0 0 0 255))
                          (make-rc-fill-rectangle 0.47 0.495 0.06 0.01 '#(255 255 255 255))
                          (make-rc-fill-rectangle 0.495 0.46 0.01 0.08 '#(255 255 255 255)))))
                       ((and (list? e) (equal? (car e) 'BLANK))
                        (list (standard-timepoint
                               (second e)
                               (make-rc-fill-rectangle 0 0 1 1 '#(0 0 0 255))
                               (make-rc-render #f))))
                       ((and (list? e) (= (length e) 3) (equal? (car e) 'PLAY))
                        (list (standard-timepoint
                               (/ fps)
                               (make-rc-load-video (string-append stimuli-directory "/" (second e)) 0)
                               (make-rc-show-video-frame 0 0 0 1 1 255))
                              (standard-timepoint
                               (/ fps)
                               (make-rc-advance-video-frame 0)
                               (make-rc-show-video-frame 0 0 0 1 1 255)
                               (make-rc-loop (- (* fps (third e)) 2))
                               (make-rc-start-volume #f))))
                       ((and (list? e) (= (length e) 2) (equal? (car e) 'PLAY))
                        (list (standard-timepoint
                               (/ fps)
                               (make-rc-load-video (string-append stimuli-directory "/" (second e)) 0)
                               (make-rc-advance-video-frame 0)
                               (make-rc-advance-video-frame 0)
                               (make-rc-advance-video-frame 0)
                               (make-rc-advance-video-frame 0)
                               (make-rc-show-video-frame 0 0 0 1 1 255)
                               (make-rc-advance-video-frame 0))
                              (standard-timepoint
                               (/ fps)
                               (make-rc-stop-on-volume-without-clearing #f)
                               (make-rc-advance-video-frame 0)
                               (make-rc-show-video-frame 0 0 0 1 1 255)
                               (make-rc-loop (- frames 5)))
                              (list
                               (make-rc-stop-on-volume-and-clear #f)
                               (make-rc-fill-rectangle 0 0 1 1 '#(0 0 0 255))
                               (make-rc-fill-rectangle 0.47 0.495 0.06 0.01 '#(255 255 255 255))
                               (make-rc-fill-rectangle 0.495 0.46 0.01 0.08 '#(255 255 255 255))
                               (make-rc-render #f)
                               (make-rc-wait-for-volume #f))))
                       (else (error "Unknown run command" e))))
                (but-last (read-object-from-file (string-append runs-directory "/" d))))))
             (directory-list runs-directory)))
  (set! *sequence-name* 'run))
 (imlib-add-path-to-font-path
  (cond ((file-exists? "/usr/share/fonts/truetype/ttf-dejavu")
         "/usr/share/fonts/truetype/ttf-dejavu")
        ((file-exists? "/usr/share/fonts/dejavu")
         "/usr/share/fonts/dejavu")
        ((file-exists? "/usr/share/fonts/TTF")
         "/usr/share/fonts/TTF")
        (else (error "Can't find a font directory"))))
 ((c-function void ("setup_number_keys" int)) slices/tr)
 (gui '()))

(apply main (command-line-arguments))
