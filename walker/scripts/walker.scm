;; =====================================================================
;; walker.scm
;;
;; Minimal walker: adjacent-pair counting, triggered by every
;; versus-teach call (inference.scm wires the hook). Accumulates
;; PairAtoms with count properties so that downstream MI / clustering
;; iterations have a substrate to work from.
;;
;; This is the simplest useful version. MI computation, wake/sleep
;; phases, and clustering come in later iterations. See next/walker.md
;; for the roadmap.
;; =====================================================================

(use-modules (opencog)
             (ice-9 format)
             (srfi srfi-1)
             (srfi srfi-13))

(define versus-pair-prefix "pair:")
(define versus-pair-separator ">>")

(define (versus-pair-name w1 w2)
  (string-append versus-pair-prefix w1 versus-pair-separator w2))

(define (versus-pair-name? atom-name)
  (string-prefix? versus-pair-prefix atom-name))

(define (versus-ensure-pair-atom w1 w2)
  (let ((atom (Concept (versus-pair-name w1 w2))))
    (versus-init-atom atom "pairs")
    atom))

(define (versus-fragment-words fragment-atom)
  "Return the cleaned word list of a FragmentAtom's surface text."
  (filter (lambda (w) (not (string-null? w)))
          (string-split
            (versus-fragment-surface (cog-name fragment-atom))
            #\space)))

;; --- versus-walker-tick: the thing you call per observation --------------

(define-public (versus-walker-tick fragment-atom)
  "Process one FragmentAtom: for each adjacent word pair in the
fragment's surface text, ensure a PairAtom exists and increment its
count. Returns the number of pairs processed."
  (let ((words (versus-fragment-words fragment-atom)))
    (let loop ((ws words) (processed 0))
      (if (< (length ws) 2)
        processed
        (let* ((w1 (car ws))
               (w2 (cadr ws))
               (pair (versus-ensure-pair-atom w1 w2)))
          (versus-increment-count! pair)
          (loop (cdr ws) (+ processed 1)))))))

;; --- Observability -------------------------------------------------------

(define-public (versus-all-pairs)
  "All PairAtoms currently in the atomspace."
  (filter
    (lambda (a) (versus-pair-name? (cog-name a)))
    (cog-get-atoms 'ConceptNode)))

(define (versus-pair-count pair-atom)
  (let ((val (cog-value pair-atom (Predicate "count"))))
    (if val (cog-value-ref val 0) 0.0)))

(define (versus-format-pair-line pair-atom)
  (format #f "  ~a (count=~,1f)"
          (cog-name pair-atom)
          (versus-pair-count pair-atom)))

(define-public (versus-walker-stats)
  "Human-readable snapshot of walker state: fragment count, pair count,
top-5 pairs by count. Called by the :stats command in chat.py."
  (let* ((fragments (versus-all-fragments))
         (pairs (versus-all-pairs))
         (sorted-pairs (sort pairs
                         (lambda (a b)
                           (> (versus-pair-count a)
                              (versus-pair-count b)))))
         (top-n (if (> (length sorted-pairs) 5)
                  (list-head sorted-pairs 5)
                  sorted-pairs))
         (top-lines (map versus-format-pair-line top-n))
         (top-block (if (null? top-lines)
                      "  <no pairs yet>"
                      (string-join top-lines "\n"))))
    (format #f "fragments=~a pairs=~a\ntop pairs by count:\n~a"
            (length fragments)
            (length pairs)
            top-block)))
