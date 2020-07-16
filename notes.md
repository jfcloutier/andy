# A directed graph of Generative Models (GMs)

Enactive cognition is realized by the interplay of GMs with each others and their perceived environment

A GM is responsible for a more or less abstract domain of cognition

A GM defines a core set of conjectured beliefs (its domain of beliefs). 

A GM G1 is implicitly a child to parent GM G2 is G1 can hold beliefs that are perceptions to G2 from which G2 constructs its own beliefs

A belief is either about an object in the environment, including self (e.g. safe(self)), or about an ordered pair of objects (e.g. closer-to(self, Obstacle)

A GM's perceptions are predicted beliefs of other (child) GMs, possibly corrected via prediction errors from the child GMs.

Each belief belongs to at least one set (with > 1 members) of mutually exclusive beliefs.
 * Each such set identifies one default belief

A GM can have multiple (more abstract and implied) parent GMs

GMs form an acyclic, parent-child directed graph with possibly multiple root nodes

A GM can abduce new beliefs via its `theory` (a logic program) that evolves as experience is gained. 

A GM is an actor in the sense of the Actor Model; it is a process that holds a state and communicates with other decoupled GMs via broadcasted event messages

# Lifecycle

 Each GM asynchronously goes through a lifecycle of successive, time-boxed rounds.
 
 For each round, a GM sequentially starts up, listens, acts, shuts down
 
 A GM updates its set of beliefs and perceptions whenever it receives ("hears") predictions about its beliefs from parent GMs, or prediction errors from children
  * Receiving a predicted belief B1 (from a parent GM) removes any currently held contradictory belief B2 if B1 and B2 are mutually exclusive
  * Receiving a prediction error (from a child GM) replaces in the perceptions the contradicted prediction
  * Predictions it receives from parent GMs are
    * `goal beliefs` the GM is expected to realize via actions
    * `opinion beliefs` the GM is expected to test possibly via actions
A GM immediately emits updated belief predictions and/or prediction errors whenever its beliefs change

A GM always maintains a maximal set of beliefs (one from each group of mutually exclusive beliefs conjecturable by the GM) that's consistent with the latest perceptions and predicted beliefs from parent GMs
  * If no belief in a mutual exclusion set is predicted in a given round, the latest prior belief in that set is carried over to the current round.
  * If none, the default belief in the set is the one held

A GM maintains a `theory` about itself and its environment (a generated logic program) it applies to: 
  * Update its beliefs when its perceptions are updated from receiving prediction errors,
  * Make predictions (about child GM beliefs) when its own beliefs change
  * Select actions to realize predicted goal beliefs and try to prove wrong predicted opinion beliefs

When starting up, a GM:
  * Accepts buffered, relevant predictions from parent GMs and prediction errors from child GMs emitted while it was not listening
  * Updates its set of held beliefs

When listening (to events boradcasted by other GMs), it:
  * Receives and processes predictions about its own beliefs (from implicitly parent GMs), and prediction errors from (implicitly) child GMs
  * It completes this phase after a set amount of time has elapsed since the GM has emitted any prediction in this round

When acting, it:
  * Selects actions expected to achieve its current goal beliefs and test its current opinion beliefs
  * Carries out these actions

When shutting down, it:
  * Commits the round to memory
  * Drops from memory rounds from too long ago
  * Triggers update of its theory to make sense of all remembered rounds

# Goal vs opinion beliefs

A GM gets goal and (default) opinion beliefs top-down from parent GMs (the parents mark the belief as goal or opinion). 

The GM validates its beliefs by predicting consequent perceptions (predicted beliefs of child GMs) and processing prediction errors from child GMs. If one of its predicted beliefs is contradicted by a newly held belief, the GM raises a prediction error to be received by parent GMs.

The essential differences between a goal and an opinion belief are:

* A GM is expected to select and execute actions (to act) so as to *realize* a goal belief
* A GM is expected to act to *test* an opinion belief, i.e. to make it valid or invalid (both are equally desirable)

"If I am hungry then I predict that I am eating" (goal)
"If I am over food then I predict that I see white under me" (opinion)

In effect, the goal vs. opinion nature of the predicted belief contrains the choice of actions; to attempt making it true if it's a goal (it is currently not held), or to test it if it's an opinion (it is currently held).

How a GM tests an opinion belief B1 predicted by a parent GM: 
  * At a minimum, the GM makes predictions about inferred child GM beliefs (and so on), possibly leading to prediction errors (from down into the GM tree), and a revision of belief B1
  * If the GM is at the end of the round and opinion belief B1 is still held, the GM takes an action that *challenges* belief B1, if there is such action.

# About actions

A GM is something of a scientist: It is an *optimist* about its goal beliefs (it keeps trying to achieve them), a *skeptic* about its opinion beliefs (it tests them), and an *experimentalist* about what actions have what effects on its beliefs (it tries alternatives to see what else works).

GM has a repertoire, possibly empty, of actions (parameterized) it can take, e.g. move forward with speed=fast and duration=2 secs.

Each intent parameter has a value domain, e.g. speed in {fast, normal, slow}, duration in [0.25, 2.0]

An action can be either `reactive` or `causative`.

A reactive action is associated *a priori* (not from theory) with a belief B1 and is to be taken when a belief B1 is held after a contradictory belief B2 was held. For example, saying "I am hungry" when the "not hungry" belief is flipped to the "hungry" belief.

A causative action re. belief B1 is an action that could causes belief B1 to become held (according to the GM's theory) in the next round or the one after.

# Which actions to take and when

A causative action is dynamically associated with belief B1 according to the GM builds `theory` of itself in its environment (a generated logic program).

If a GM was predicted to hold a goal belief B1 and does not hold it (it holds a contradictory belief B2), it will choose a causative action that, according to its current theory, could realize belief B1, i.e flip from holding a contradictory belief B2 to holding belief B1.

If a GM holds an opinion belief B1, it will choose a causative action A1, if there is one, such that, according to the GM's theory, action A1 causes a contradictory belief B2 to flip to B1 but does not cause flipping from B1 to B2; the GM is testing whether it is correctly holding belief B1, not trying to flip it to B2.

If a GM has insufficient evidence whether an action A1 in its repertoire affects belief B1, it can choose action A1 to gather such evidence. A GM experiments to avoid bulding a disparity of positive or negative evidence within its repertoire of actions.

If an action has been taken in the current round to achieve goal belief B1, no other action known to alter belief B1 should be taken, in this or the next two rounds. This is to give the action time to take perceived effect and it keeps a GM from "thrashing about".

If an action has been taken in the current round to test opinion belief B1, no other action in this and future rounds to test belief B1 should be taken while the belief is being continuously held. This is to prevent a GM from displaying "OCD-like" behaviors.

# The GM's theory (of itself in its environment) as generated logic program 

The GM's `theory` is a (re)generated logic program that makes static and causal inferences about beliefs (its own and those predicted of child GMs) and about actions.

  * Static: 
    * Beliefs => ~Beliefs (constraints on mutually held beliefs) - core given a priori

    * Perceptions => Beliefs (inferring beliefs held from perceptions) - core given a priori
      * using forward inferences: the GM infers new beliefs from its current and prior perceptions, 
      * using backward inferences: the GM infers incoming perceptions (i.e. predictions on child GM beliefs) given current beliefs

  * Causal: 
    * Beliefs x Actions =~> Beliefs (inferring changes in beliefs from actions taken) - induced from experience
      * backward: the GM infers which actions would cause beliefs in the near-future gien current beliefs
      * forward: the GM infers near-future beliefs from actions taken in this round

Inferred beliefs can be about known objects (self, other) and about "hidden", i.e. abduced objects in the GM's environment.

# GM theories

A GM (re)generates a logic program from the data in past rounds that

* infers a GM's beliefs from its perceptions
* infers a GM's predictions (next beliefs of child GMs) from current beliefs and past perceptions
* infers a GM's actions from received predicted beliefs and current beliefs

A GM's frame borrows from an a priori global frame which defines:
  * types: robot, food, obstacle
  * objects: self (a robot), other (a robot).
  * unary and binary (belief) predicates

Each GM pre-defines a priori theory elements:
  * constraints
      * mutually exclusive unary beliefs
      * "full unary beliefs" (for each applicable object, one belief from each of the mutually exclusive belief sets)
  * static rules (how to infer beliefs form perceptions)

With experience (rounds completed), each GM *augments* its a priori theory elements with
  * causal rules (how to effect changes in beliefs via actions)
  * abduced objects 
  * induced belief predicates 
  * XOr belief set constraints

Spatial unity contraints?

## Challenges

The Apperception Engine was developed under assumptions that are not true of GMs, namely:

* Because GMs runs asynchronously and contribute to the perceptions of other GMs, any effects of an action taken at the end of round N may not be perceived by it during round N + 1 but only at round N + 2 or even later.

* Instead of generating one theory, we are generating multiple theories (one per GM) and they are interlinked implicitly by the parent-child relationships between GMs.

* Can a GM theory express perceptions in terms of induced belief predicates and abduced objects? 
  * If so some other GM needs to express its own beliefs in these terms for this to be meaningful
  * Doing so must not break the acyclicity constraint in the implicit parent-child GM graph
  * How is this implemented if GM build their theories asynchronously?







