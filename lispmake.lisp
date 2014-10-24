(in-package :lispmake)

;; lispmake, written by Matthew Veety, et al.
;; (c) Matthew Veety 2012,2013,2014. Under BSD License.
;; 
;; This is a hacked together program designed to generate the build
;; files that are required for a client's lisp set up. If you find
;; bugs or better ways to do things then send in patches.
;; 
;; Things that need doing:
;;     * Support for clisp, cmucl, ccl, and I guess others
;;     * build targets (ala make) (could be a plugin)
;;     * testing. It works for me, it might not for you

;(defvar *debugging* (not nil))  ;; enable or disable debugging output
(defvar *debugging* nil)
(defvar *lispmake-version* 11)
(defvar *sources* nil)
(defvar *outfile* nil)
(defvar *lm-package* nil)
(defvar *toplevel* nil)
(defvar *quickloads* nil)
(defvar *generate* nil)
(defvar *compile-files* nil)
(defvar *lisp-executable* nil)
(defvar *lisp-target* 'default)
(defvar *plugins* '((:package pl-package)
		    (:toplevel pl-toplevel)
		    (:file pl-file)
		    (:output pl-output)
		    (:quicklisp pl-quicklisp)
		    (:generate pl-generate)))
(defvar *pregen-hooks* nil)
(defvar *postgen-hooks* nil)

(defun lm-error (function explain)
  (format t "lispmake: error: ~A: ~A~%" function explain)
  nil)

(defun lm-warning (function explain)
  (format t "lispmake: warning: ~A: ~A~%" function explain)
  nil)

(defun lm-debug (function explain)
  (if *debugging*
      (format t "lispmake: debug: ~A: ~A~%" function explain))
  nil)

(defmacro lm-advdebug (function fmt &rest forms)
  (if *debugging*
      (progn
	(format t "lispmake: debug: ~A: " function)
	`(format t ,fmt ,@forms)
	(format t "~%"))))

(defun loadfile (outstream fname)
  (format outstream "(load #P\"~A\")~%" (car fname)))

(defun quickloads (outstream library)
  (format outstream "(ql:quickload '~A)~%" (car library)))

(defun pl-package (args)
  (setf *lm-package* args))

(defun pl-toplevel (args)
  (setf *toplevel* args))

(defun pl-file (args)
  (if (equal (type-of (type-of args)) 'cons)
      (dolist (x args)
	(setf *sources* (append *sources* (list x))))
      (setf *sources* (append *sources* (list args)))))

(defun pl-output (args)
  (setf *outfile* args))

(defun pl-quicklisp (args)
  (if (equal (type-of args) 'cons)
      (dolist (x args)
	(setf *quickloads* (append *quickloads* (list x))))
      (setf *quickloads* (append *quickloads* (list args)))))

(defun pl-generate (args)
  (declare (ignore args))
  (setf *generate* (not *generate*)))

(defun pl-eval (args)
  (lm-debug "pl-eval" "evaluating lisp")
  (let ()
    (eval args)))

(defun pl-lisp (args)
  (lm-debug "pl-lisp" "setting default lisp")
  (setf *lisp-target* (car args)))

(defun generate ()
  (with-open-file (mkfile "build.lisp" :direction :output :if-exists :supersede)
    (format mkfile ";; autogenerated by lispmake revision ~A~%;; DO NOT EDIT~%" *lispmake-version*)
    (run-plugin-pregen mkfile)
    (dolist (x *quickloads*)
      (lm-debug "generate" "generating quicklisp forms")
      (quickloads mkfile x))
    (dolist (x *sources*)
      (lm-debug "generate" "generating load forms")
      (loadfile mkfile x))
    (lm-debug "generate" "generating save-and-die form")
    (if *generate*
	(buildexe mkfile *outfile* *lm-package* *toplevel* *lisp-target*))
    (force-output mkfile)
    (run-plugin-postgen mkfile)))

(defun runner (forms)
  (if (not (equal (type-of forms) 'cons))
      (lm-error "runner" "form not of type cons in LMakefile")
      (progn
	(let ((cmd (car forms))
	      (plug nil))
	  (dolist (x *plugins*)
	    (setf plug (car x))
	    (if (equal cmd plug)
		(progn
		  (lm-debug "runner" "running plugin")
		  (funcall (cadr x) (cdr forms)))))))))

(defun main ()
  (if *debugging*
      (format t "lispmake r~A~%" *lispmake-version*)
      (disable-debugger))
  (install-plugin :plugin 'pl-plugin)
  (install-plugin :eval 'pl-eval)
  (install-plugin :lisp 'pl-lisp)
  (install-plugin :compile-file 'pl-compile-file)
  (install-plugin :build-with 'pl-lisp-executable)
  (install-pregen-hook 'pl-compile-file-pregen)
  (install-postgen-hook 'run-build-process)
  (export '(install-plugin install-pregen-hook install-postgen-hook))
  (with-open-file (lmkfile "LMakefile")
    (loop for form = (read lmkfile nil nil)
	 until (eq form nil)
	 do (progn
	      (lm-debug "main" "reading form")
	      (runner form)))
  (if (or (equal *lm-package* nil)
	  (equal *generate* nil)
	  (equal *sources* nil)
	  (equal *toplevel* nil)
	  (equal *outfile* nil))
      (lm-error "main" "you did not run a required operation")
      (progn
	(lm-debug "main" "generating build.lisp")
	(generate)))))

