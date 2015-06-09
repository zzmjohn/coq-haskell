Require Import Hask.Prelude.
Require Import Hask.Control.Lens.
Require Import Hask.Control.Monad.
Require Import Hask.Control.Monad.Trans.Free.

(* Set Universe Polymorphism. *)

Generalizable All Variables.

Inductive Proxy (a' a b' b : Type) (m : Type -> Type) (r : Type) : Type :=
  | Request of a' & (a  -> Proxy a' a b' b m r)
  | Respond of b  & (b' -> Proxy a' a b' b m r)
  | M : forall x, (x -> Proxy a' a b' b m r) -> m x -> Proxy a' a b' b m r
  | Pure of r.

Arguments Request {a' a b' b m r} _ _.
Arguments Respond {a' a b' b m r} _ _.
Arguments M {a' a b' b m r x} _ _.
Arguments Pure {a' a b' b m r} _.

Definition Proxy_bind {a' a b' b c d} `{Monad m}
  (f : c -> Proxy a' a b' b m d) (p0 : Proxy a' a b' b m c) :
  Proxy a' a b' b m d :=
  let fix go p := match p with
    | Request a' fa  => Request a' (go \o fa)
    | Respond b  fb' => Respond b  (go \o fb')
    | M _     f  t   => M (go \o f) t
    | Pure    r      => f r
    end in
  go p0.

Instance Proxy_Functor `{Monad m} {a' a b' b} :
  Functor (Proxy a' a b' b m) := {
  fmap := fun _ _ f p0 => Proxy_bind (Pure \o f) p0
}.

Instance Proxy_Applicative `{Monad m} {a' a b' b} :
  Applicative (Proxy a' a b' b m) := {
  pure := fun _ => Pure;
  ap   := fun _ _ pf px => Proxy_bind (fmap ^~ px) pf
}.

Instance Proxy_Monad `{Monad m} {a' a b' b} :
  Monad (Proxy a' a b' b m) := {
  join := fun _ x => Proxy_bind id x
}.

Fixpoint runEffect `{Monad m} `(p : Proxy False unit unit False m r) : m r :=
  match p with
  | Request v f => False_rect _ v
  | Respond v f => False_rect _ v
  | M _     f t => t >>= (runEffect \o f)
  | Pure    r   => pure r
  end.

Definition respond {x' x a' a m} (z : a) : Proxy x' x a' a m a' :=
  Respond z Pure.

Definition request {x' x a' a m} (z : x') : Proxy x' x a' a m x :=
  Request z Pure.

Definition Producer := Proxy False unit unit.
Definition Producer' b m r := forall x' x, Proxy x' x unit b m r.

Definition yield {a x' x m} (z : a) : Proxy x' x unit a m unit :=
  let go : Producer' a m unit := fun _ _ => respond z in @go x' x.

Definition forP `{Monad m} {x' x a' b' b c' c} (p0 : Proxy x' x b' b m a')
  (fb : b -> Proxy x' x c' c m b') : Proxy x' x c' c m a' :=
  let fix go p := match p with
    | Request x' fx  => Request x' (go \o fx)
    | Respond b  fb' => fb b >>= (go \o fb')
    | M _     f  t   => M (go \o f) t
    | Pure       a   => Pure a
    end in
  go p0.

Notation "x //> y" := (forP x y) (at level 60).

Notation "f />/ g" := (fun a => f a //> g) (at level 60).

Definition rofP `{Monad m} {y' y a' a b' b c} (fb' : b' -> Proxy a' a y' y m b)
  (p0 : Proxy b' b y' y m c) : Proxy a' a y' y m c :=
  let fix go p := match p with
    | Request b' fb  => fb' b' >>= (go \o fb)
    | Respond x  fx' => Respond x (go \o fx')
    | M _     f  t   => M (go \o f) t
    | Pure       a   => Pure a
    end in
  go p0.

Notation "x >\\ y" := (rofP x y) (at level 60).

Notation "f \>\ g" := (fun a => f >\\ g a) (at level 60).

Fixpoint pushR `{Monad m} {a' a b' b c' c r} (p0 : Proxy a' a b' b m r)
  (fb : b -> Proxy b' b c' c m r) {struct p0} : Proxy a' a c' c m r :=
  let fix go p := match p with
    | Request a' fa  => Request a' (go \o fa)
    | Respond b  fb' =>
        let fix go' p := match p with
          | Request b' fb  => go (fb' b')
          | Respond c  fc' => Respond c (go' \o fc')
          | M _     f  t   => M (go' \o f) t
          | Pure       a   => Pure a
          end in
        go' (fb b)
    | M _     f  t   => M (go \o f) t
    | Pure       a   => Pure a
    end in
  go p0.

Notation "x >>~ y" := (pushR x y) (at level 60).

Notation "f >~> g" := (fun a => f a >>~ g) (at level 60).

Fixpoint pullR `{Monad m} {a' a b' b c' c r} (fb' : b' -> Proxy a' a b' b m r)
  (p0 : Proxy b' b c' c m r) {struct p0} : Proxy a' a c' c m r :=
  let fix go p := match p with
    | Request b' fb  =>
        let fix go' p := match p with
          | Request a' fa  => Request a' (go' \o fa)
          | Respond b  fb' => go (fb b)
          | M _     f  t   => M (go' \o f) t
          | Pure       a   => Pure a
          end in
        go' (fb' b')
    | Respond c  fc' => Respond c (go \o fc')
    | M _     f  t   => M (go \o f) t
    | Pure       a   => Pure a
    end in
  go p0.

Notation "x +>> y" := (pullR x y) (at level 60).

Notation "f >+> g" := (fun a => f +>> g a) (at level 60).

Definition each `{Monad m} {a} : seq a -> Producer a m unit :=
  mapM_ yield.

Fixpoint toListM `{Monad m} `(p : Producer a m unit) : m (seq a) :=
  match p with
  | Request v _  => False_rect _ v
  | Respond x fu => cons x <$> toListM (fu tt)
  | M _     f t  => t >>= (toListM \o f)
  | Pure    _    => pure [::]
  end.

(* jww (2015-05-30): Make \o bind tighter than >>= *)

Module PipesLaws.

Include MonadLaws.

Require Import FunctionalExtensionality.

Tactic Notation "reduce_proxy" ident(IHu) tactic(T) :=
  elim=> [? ? IHu|? ? IHu|? ? IHu| ?]; T;
  try (try move => m0; f_equal; extensionality RP_A; exact: IHu).

Program Instance Proxy_FunctorLaws `{MonadLaws m} {a' a b' b} :
  FunctorLaws (Proxy a' a b' b m).
Obligation 1. by reduce_proxy IHx simpl. Qed.
Obligation 2. by reduce_proxy IHx simpl. Qed.

Program Instance Proxy_ApplicativeLaws `{MonadLaws m} {a' a b' b} :
  ApplicativeLaws (Proxy a' a b' b m).
Obligation 1. reduce_proxy IHx simpl. Qed.
Obligation 2.
  move: u; reduce_proxy IHu (rewrite /funcomp /= /funcomp).
  move: v; reduce_proxy IHv (rewrite /funcomp /= /funcomp).
  by move: w; reduce_proxy IHw simpl.
Qed.

Program Instance Proxy_MonadLaws `{MonadLaws m} {a' a b' b} :
  MonadLaws (Proxy a' a b' b m).
Obligation 1. reduce_proxy IHx simpl. Qed.
Obligation 2. by reduce_proxy IHx simpl. Qed.
Obligation 4. by reduce_proxy IHx simpl. Qed.

Theorem respond_distrib `{MonadLaws m} :
  forall (x' x a' a b' b c' c r : Type)
         (f : a  -> Proxy x' x b' b m a')
         (g : a' -> Proxy x' x b' b m r)
         (h : b  -> Proxy x' x c' c m b'),
  (f >=> g) />/ h =1 (f />/ h) >=> (g />/ h).
Proof.
  move=> ? ? ? ? ? ? ? ? ? f ? ? x.
  rewrite /kleisli_compose.
  elim: (f x) => // [? ? IHx|? ? IHx|? ? IHx].
  - rewrite /bind /=.
    f_equal.
    extensionality a1.
    exact: IHx.
  - apply functional_extensionality in IHx.
    by rewrite /= /funcomp IHx /bind /funcomp
               -join_fmap_fmap_x fmap_comp_x
               -join_fmap_join_x fmap_comp_x.
  - move=> m0.
    rewrite /bind /=.
    f_equal.
    extensionality y.
    exact: IHx.
Qed.

Theorem request_distrib `{MonadLaws m} :
  forall (y' y a' a b' b c' c r : Type)
         (f : c -> Proxy b' b y' y m c')
         (g : c'  -> Proxy b' b y' y m r)
         (h : b' -> Proxy a' a y' y m b),
  h \>\ (f >=> g) =1 (h \>\ f) >=> (h \>\ g).
Proof.
  move=> ? ? ? ? ? ? ? ? ? f ? ? x.
  rewrite /kleisli_compose.
  elim: (f x) => // [? ? IHx|? ? IHx|? ? IHx].
  - apply functional_extensionality in IHx.
    by rewrite /= /funcomp IHx /bind /funcomp
               -join_fmap_fmap_x fmap_comp_x
               -join_fmap_join_x fmap_comp_x.
  - rewrite /bind /=.
    f_equal.
    extensionality a1.
    exact: IHx.
  - move=> m0.
    rewrite /bind /=.
    f_equal.
    extensionality y.
    exact: IHx.
Qed.

Require Import Hask.Control.Category.

(*
Program Instance CNat : Category := {
  ob     := Type -> Type;
  hom    := fun A B => forall x, A x -> B x;
  c_id   := fun A _ => id;
  c_comp := fun _ _ _ f g s => f s \o g s
}.

Definition Hom (a : Type) := forall b, a -> b.

Definition Proxy_ (a' a b' b : Type) (m : Type -> Type) (r : Type) : Type :=
     Hom a' ~{CNat}~> Hom a  ->
     Hom b  ~{CNat}~> Hom b' ->
  Hom \o m  ~{CNat}~> Hom \o id ->
   Hom unit ~{CNat}~> Hom r.
*)

Program Instance Respond_Category {x' x a'} `{MonadLaws m} : Category := {
  ob     := Type;
  hom    := fun A B => A -> Proxy x' x a' B m a';
  c_id   := fun A => @respond x' x a' A m;
  c_comp := fun _ _ _ f g => g />/ f
}.
Obligation 1. (* Right identity *)
  extensionality z.
  exact: join_fmap_pure_x.
Qed.
Obligation 2. (* Left identity *)
  extensionality z.
  move: (f z).
  by reduce_proxy IHx (rewrite /= /bind /funcomp /=).
Qed.
Obligation 3. (* Associativity *)
  extensionality z.
  elim: (h z) => // [? ? IHx|? ? IHx|? ? IHx].
  - rewrite /=.
    f_equal.
    extensionality a1.
    exact: IHx.
  - apply functional_extensionality in IHx.
    by rewrite /= /funcomp -IHx respond_distrib.
  - move=> m0.
    rewrite /=.
    f_equal.
    rewrite /funcomp.
    extensionality y.
    exact: IHx.
Qed.

(* Theorem respond_zero *)

Program Instance Request_Category {x a' a} `{MonadLaws m} : Category := {
  ob     := Type;
  hom    := fun A B => B -> Proxy A x a' a m x;
  c_id   := fun A => @request A x a' a m;
  c_comp := fun _ _ _ f g => g \>\ f
}.
Obligation 1. (* Right identity *)
  extensionality z.
  move: (f z).
  by reduce_proxy IHx (rewrite /= /bind /funcomp /=).
Qed.
Obligation 2. (* Left identity *)
  extensionality z.
  exact: join_fmap_pure_x.
Qed.
Obligation 3. (* Associativity *)
  extensionality z.
  elim: (f z) => // [y p IHx|? ? IHx|? ? IHx].
  - apply functional_extensionality in IHx.
    by rewrite /= /funcomp IHx request_distrib.
  - rewrite /=.
    f_equal.
    extensionality a1.
    exact: IHx.
  - move=> m0.
    rewrite /=.
    f_equal.
    rewrite /funcomp.
    extensionality y.
    exact: IHx.
Qed.

(* Theorem request_zero *)

CoInductive CoProxy (a' a b' b : Type) (m : Type -> Type) (r : Type) : Type :=
  | CoRequest of a' & (a  -> CoProxy a' a b' b m r)
  | CoRespond of b  & (b' -> CoProxy a' a b' b m r)
  | CoM : forall x, (x -> CoProxy a' a b' b m r) -> m x -> CoProxy a' a b' b m r
  | CoPure of r.

Arguments CoRequest {a' a b' b m r} _ _.
Arguments CoRespond {a' a b' b m r} _ _.
Arguments CoM {a' a b' b m r x} _ _.
Arguments CoPure {a' a b' b m r} _.

CoFixpoint push `{Monad m} {a' a r} : a -> CoProxy a' a a' a m r :=
  CoRespond ^~ (CoRequest ^~ push).

Fixpoint render (n : nat) `(dflt : r) `(co : CoProxy a' a b' b m r) :
  Proxy a' a b' b m r :=
  if n isn't S n' then Pure dflt else
  match co with
    | CoRequest a' fa => Request a' (render n' dflt \o fa)
    | CoRespond b  fb => Respond b  (render n' dflt \o fb)
    | CoM _     f  t  => M (render n' dflt \o f) t
    | CoPure       a  => Pure a
    end.

Definition stream `(co : Proxy a' a b' b m r) : CoProxy a' a b' b m r :=
  let cofix go p := match p with
    | Request a' fa => CoRequest a' (go \o fa)
    | Respond b  fb => CoRespond b  (go \o fb)
    | M _     f  t  => CoM (go \o f) t
    | Pure       a  => CoPure a
    end in
  go co.

Inductive pushR_ev {a' a b' b m r} : CoProxy a' a b' b m r -> Prop :=
  | ev_pushR_req  : forall aa' fa, pushR_ev (CoRequest aa' fa)
  | ev_pushR_res  : forall bb  fb fb',
      pullR_ev (fb' bb) -> pushR_ev (CoRespond bb fb)
  | ev_pushR_mon  : forall x g (h : m x), pushR_ev (CoM g h)
  | ev_pushR_pure : forall x : r, pushR_ev (CoPure x)

with pullR_ev {a' a b' b m r} : CoProxy a' a b' b m r -> Prop :=
  | ev_pullR_req  : forall aa' fa fa',
      pushR_ev (fa' aa') -> pullR_ev (CoRequest aa' fa)
  | ev_pullR_res  : forall bb  fb, pullR_ev (CoRequest bb fb)
  | ev_pullR_mon  : forall x g (h : m x), pullR_ev (CoM g h)
  | ev_pullR_pure : forall x : r, pullR_ev (CoPure x).

Lemma eventually_pushR_inv {a' a b' b m r} : forall bb fb,
  @pushR_ev a' a b' b m r (CoRespond (bb : b) fb)
    -> forall x : b', pushR_ev (fb x).
Proof.
Admitted.

Lemma eventually_pullR_inv {a' a b' b m r} : forall aa' fa,
  @pullR_ev a' a b' b m r (CoRequest (aa' : a') fa)
    -> forall x : a, pullR_ev (fa x).
Proof.
Admitted.

(*
Require Import Coq.Program.Equality.
Import EqNotations.

Fixpoint pre_pushR {a' a b' b m r} (x : CoProxy a' a b' b m r)
  (d : pushR_ev x) {struct d} :
  a' * CoProxy a' a b' b m r :=
  match x as z return x = z -> a' * CoProxy a' a b' b m r with
  | CoRequest a' fa  => fun heq => (a', undefined)
  | CoRespond bb fb' => fun heq =>
      pre_pushR (fb' undefined)
                (eventually_pushR_inv bb fb' d undefined)
  | CoM _     f  t   => fun heq => undefined
  | CoPure       a   => fun heq => undefined
  end (refl_equal x).
*)

(*
CoFixpoint pushR `{Monad m} {a' a b' b c' c r} (p0 : CoProxy a' a b' b m r)
  (fb : b -> CoProxy b' b c' c m r) {struct p0} : CoProxy a' a c' c m r :=
  let cofix go p := match p with
    | CoRequest a' fa  => CoRequest a' (go \o fa)
    | CoRespond b  fb' =>
        let cofix go' p := match p with
          | CoRequest b' fb  => go (fb' b')
          | CoRespond c  fc' => CoRespond c (go' \o fc')
          | CoM _     f  t   => CoM (go' \o f) t
          | CoPure       a   => CoPure a
          end in
        go' (fb b)
    | CoM _     f  t   => CoM (go \o f) t
    | CoPure       a   => CoPure a
    end in
  go p0.
*)

(*
Program Instance Push_Category
  (n : nat) (_ : n > 0) {r} (dflt : r) `{MonadLaws m} :
  Category := {
  ob     := Type * Type;
  hom    := fun A B => snd A -> CoProxy (fst A) (snd A) (fst B) (snd B) m r;
  c_id   := fun A => @push m _ (fst A) (snd A) r;
  c_comp := fun _ _ _ f g => g >~> f
}.
Obligation 1. (* Right identity *)
  rewrite /stream /= in f *.
  case: n => // [n'] in H1 *.
  extensionality z => /=.
  move: (f z).
  destruct f0.
  simpl.
  reduce_proxy IHx idtac.
  f_equal.
  extensionality x.
  specialize (IHx x).
  rewrite -IHx.
  unfold funcomp in *. simpl in *.
  rewrite -IHx.
  rewrite /funcomp /=.
Obligation 2. (* Left identity *)
(* Obligation 3. (* Associativity *) *)
*)

(* Theorem push_zero *)

(*
Program Instance Pull_Category {x' x a'} `{MonadLaws m} : Category := {
  ob     := Type;
  hom    := fun A B => A -> Proxy x' x a' B m a';
  c_id   := fun A => @pull x' x a' A m;
  c_comp := fun _ _ _ f g => f >+> g
}.
Obligation 1. (* Right identity *)
Obligation 2. (* Left identity *)
Obligation 3. (* Associativity *)
*)

(* Theorem pull_zero *)

(* Theorem push_pull_assoc *)

(* Duals

Theorem request_id

Theorem request_comp

Theorem respond_id

Theorem respond_comp

Theorem distributivity

Theorem zero_law

Theorem involution

*)

Definition SProxy (a' a b' b : Type) (m : Type -> Type) (r : Type) : Type :=
  forall s : Type,
       (a' -> (a  -> s) -> s)           (* SRequest *)
    -> (b  -> (b' -> s) -> s)           (* SRespond *)
    -> (forall x, (x -> s) -> m x -> s) (* SM *)
    -> (r -> s)                         (* SPure *)
    -> s.

Definition ftrans (a b x : Type) := a -> (b -> x) -> x.
Notation "a -[ s ]-> b" := (ftrans a b s) (at level 50).

Definition fnat (f g : Type -> Type) (s : Type) := forall x, (f x) -[s]-> (g x).
Notation "f -[[ s ]]-> g" := (fnat f g s) (at level 50).

Definition Proxy_ (a' a b' b : Type) (m : Type -> Type) (r : Type) : Type :=
  forall s : Type,
      a' -[s]->  a  ->
      b  -[s]->  b' ->
      m -[[s]]-> id ->
   unit  -[s]->  r.

Definition toProxy `(s : SProxy a' a b' b m r) : Proxy a' a b' b m r :=
  s _ Request Respond (fun _ => M) Pure.

Fixpoint fromProxy `(p : Proxy a' a b' b m r) : SProxy a' a b' b m r :=
  fun _ req res mon k =>
    match p with
    | Request a' fa  => req a' (fun a  => fromProxy (fa  a)  _ req res mon k)
    | Respond b  fb' => res b  (fun b' => fromProxy (fb' b') _ req res mon k)
    | M _     g  h   => mon _  (fun x  => fromProxy (g x) _ req res mon k) h
    | Pure    x      => k x
    end.

Lemma SProxy_to_from : forall `(x : Proxy a' a b' b m r),
  toProxy (fromProxy x) = x.
Proof.
  move=> a' a b' b m r.
  reduce_proxy IHx
    (rewrite /toProxy;
     first [ congr (Request _)
           | congr (Respond _)
           | move=> m0; congr (M _)
           | congr (Pure _) ]).
Qed.

Axiom elim : forall `(f : a -> (b -> s) -> s) (x : a) (y : s),
  f x (const y) = y.

Axiom flip_elim : forall `(f : (b -> s) -> a -> s) (x : a) (y : s),
  f (const y) x = y.

Lemma SProxy_from_to : forall `(x : SProxy a' a b' b m r),
  fromProxy (toProxy x) = x.
Proof.
  move=> ? ? ? ? ? ? x.
  recomp.
  rewrite /fromProxy /toProxy /funcomp /=.
  (* elim E: (toProxy x) => [? ? IHu|? ? IHu|? ? IHu| ?]. *)
  (* erewrite <- IHu. *)
  (* f_equal. *)
  (* rewrite /fromProxy /=. *)
  extensionality s.
  extensionality req.
  extensionality res.
  extensionality mon.
  extensionality k.
  move: (toProxy x).
  reduce_proxy IHx
    (rewrite /fromProxy /=;
     try (move/functional_extensionality in IHx;
          try move=> m0;
          rewrite IHx ?elim ?flip_elim)).
Admitted.

Section GeneralTheorems.

Theorem toListM_each_id : forall a, toListM \o each =1 pure (a:=seq a).
Proof.
  move=> a xs.
  elim: xs => //= [x xs IHxs].
  by rewrite IHxs.
Qed.

End GeneralTheorems.

End PipesLaws.