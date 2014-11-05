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

(defvar *debugging* T)
(defvar *lispmake-version* 12)
(defvar *sources* nil)
(defvar *outfile* nil)
(defvar *lm-package* nil)
(defvar *toplevel* nil)
(defvar *quickloads* nil)
(defvar *generate* nil)
(defvar *compile-files* nil)
(defvar *lisp-executable* nil)
(defvar *do-build* nil)
(defvar *lisp-target* 'default)
(defvar *plugins* nil)
(defvar *pregen-hooks* nil)
(defvar *postgen-hooks* nil)
(defvar *lmakefile* "LMakefile")

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
  (format outstream "(load #P\"~A\")~%" fname))

(defun quickloads (outstream library)
  (format outstream "(ql:quickload '~A)~%" library))

(defun pl-package (args)
  (setf *lm-package* args))

(defun pl-toplevel (args)
  (setf *toplevel* args))

(defun pl-file (args)
  (if (stringp args)
      (setf *sources* (append *sources* (list args)))
      (if (listp args)
	  (dolist (x args)
	    (setf *sources* (append *sources* x))))))

(defun pl-output (args)
  (setf *outfile* args))

(defun pl-quicklisp (args)
  (if (symbolp args)
      (setf *quickloads* (append *quickloads* (list args)))
      (if (listp args)
	  (dolist (x args)
	    (setf *quickloads* (append *quickloads* x))))))

(defun generate ()
  (with-open-file (mkfile "build.lisp" :direction :output :if-exists :supersede)
    (format 
     mkfile 
     ";; autogenerated by lispmake revision ~A~%;; DO NOT EDIT~%"
     *lispmake-version*)
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
    (run-plugin-postgen mkfile))
  (if *debugging*
      (format t "lispmake: doing build...~%"))
  (if *do-build*
      (run-build-process)))

(defun runner (forms)
  (if (not (listp forms))
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
  (handle-options)
  (if *debugging*
      (format t "lispmake r~A~%" *lispmake-version*)
      (disable-debugger))
  (loop (print (eval (read))))
  (install-plugin :package 'pl-package)
  (install-plugin :toplevel 'pl-toplevel)
  (install-plugin :file 'pl-file)
  (install-plugin :output 'pl-output)
  (install-plugin :quicklisp 'pl-quicklisp)
  (install-plugin :generate
		  (lambda (args)
		    (declare (ignore args))
		    (setf *generate* (not *generate*))))
  (install-plugin :plugin 'pl-plugin)
  (install-plugin :eval
		  (lambda (args)
		    (eval args)))
  (install-plugin :lisp
		  (lambda (args)
		    (setf *lisp-target* (car args))))
  (install-plugin :compile-file 'pl-compile-file)
  (install-plugin :build-with 'pl-lisp-executable)
  (install-plugin :do-build
		  (lambda (args)
		    (declare (ignore args))
		    (setf *do-build* (not *do-build*))))
  (install-pregen-hook 'pl-compile-file-pregen)
  (with-open-file (lmkfile *lmakefile*)
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

