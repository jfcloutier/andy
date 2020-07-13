# Meta-model

* A GM is an actor in the sense of the Actor Model
* A GM can have children GMs
* A GM can have multiple parent GMs
* GMs form an acyclic, parent-child directed graph with possibly multiple root nodes
* A GM defines a core set of conjectured beliefs (its domain of beliefs). 
* A GM can abduce new beliefs via its evolving `theory` (a logic program). 
* A belief is either about an object in the environment, including self (e.g. safe(self)), or about an ordered pair of objects (e.g. closer-to(self, Obstacle))
* A GM's perceptions are predicted beliefs of child GMs, possibly corrected by prediction errors from the child GMs.
* Each belief belonging to at least one set (with > 1 members) of mutually exclusive beliefs.
  * Each such set identifies one default belief

# Lifecycle

* Each GM, asynchronously of other GMs, goes through a lifecycle of successive, time-boxed rounds in which it sequentially:
  * Starts up, listens, acts, shuts down
  * A GM updates its set of beliefs and perceptions whenever it receives (belief) predictions from parents or prediction errors from children
    * Receiving a predicted belief removes any contradictory belief
    * Receiving a prediction error replaces in the perceptions the prediction it contradicts
    * Predictions it receives from parent GMs are
      * goal beliefs the GM is expected to realize via actions
      * opinion beliefs the GM is expected to validate by proving it wrong via actions, which yield prediction errors
  * A GM immediately emits belief predictions and/or prediction errors whenever its beliefs change
  * A GM always maintains a maximal set of beliefs (one from each group of mutually exclusive beliefs conjecturable by the GM) that's consistent with the latest perceptions and predicted beliefs from parent GMs
    * If no belief in a mutual exclusion set is predicted in a given round, the latest prior belief in that set is carried over to the current round.
      * If none, the default belief in the set is held
  * A GM maintains a theory about itself and its environment (a generated logic program) it applies to 
    * update its beliefs when receiving prediction errors,
    * make predictions (about child GM beliefs) when its own beliefs change
    * select actions to realize predicted goal beliefs and try to prove wrong predicted opinion beliefs
  * When starting up, a GM:
    * Accepts buffered, relevant predictions from parent GMs and prediction errors from child GMs emitted while it was not listening
    * Complete the set of held beliefs
  * When listening, it:
      * Receives and processes belief predictions from parent GMs, and prediction errors from child GMs
      * It completes this phase after a set amount of time has elapsed since the GM has emitted any prediction in this round
        * Each GM may have 
  * When acting, it:
    * Selects actions expected to achieve goal beliefs and invalidate-revalidate opinion beliefs predicted in this round
    * Carry out these actions
  * When shutting down, it:
    * Commits the round to memory
    * Drops from memory rounds from too long ago
    * Triggers update of its theory to be consistent with all remembered rounds

# Goal vs opinion beliefs

A GM gets goal and (default) opinion beliefs top-down from parent GMs (the parents mark the belief as goal or opinion). 

The GM validates its beliefs by predicting consequent perceptions (predicted beliefs of child GMs) and compiling prediction errors from child GMs. If one of its currently held beliefs is contradicted, the GM raises a prediction error to be captured by parent GMs.

The essential differences between a goal and an opinion belief are:

* A GM is expected to select and execute actions (to act) so as to *realize* a goal belief, i.e. made it valid
* A GM is expected to act to *test* an opinion belief, i.e. to make it valid or  invalid (both are equally desirable)

"If I am hungry then I predict that I am eating" (goal)
"If I am over food then I predict that I see white under me" (opinion)

In effect, the goal vs. opinion nature of the predicted belief contrains the choice of actions; to attempt making it true if it's a goal, or to test it if it's an opinion.

How a GM tests an opinion belief B1 predicted by a parent GM: 
  * at a minimum, the GM makes predictions about inferred child GM beliefs (and so on), possibly leading to prediction errors (from down into the GM tree), and a revision of belief B1
  * if at the end of the round and opinion belief B1 is still held, the GM takes an action that *challenges* belief B1, if there is one

# About actions

A GM is something of a scientist: It is an *optimist* about its goal beliefs (it keeps trying to achieve them), a *skeptic* about its opinion beliefs (it tests them), and an *experimentalist* about what actions have what effects on its beliefs (it tries alternatives to see what else works).

GM has a repertoire, possibly empty, of actions (parameterized intents) it can take, e.g. move forward with speed=fast and duration=2 secs.

Each intent parameter has a value domain, e.g. speed in {fast, normal, slow}, duration in [0.25, 2.0]

An action can be either `reactive` or `causative`.

A reactive action is statically associated with a belief B1 and is to be taken when a belief B1 is held after a contradictory belief B2 was held.

Each causative action is paired with one that reverses it, plus a transform function on the other action's parameters to get the reversing action's parameter values (typically it will be an identity function).

There is evidence that action A1 causes belief B1 if it is taken in round N where a belief B2 contradicting B1 is held and B1 is held in round N + I, where I < 3.

# Which actions to take

A causative action is to be taken to achieve belief B1. It is dynamically associated with belief B1 according to the GM's `theory` of itself in its environment (a generated logic program).

If a GM was predicted to hold a goal belief B1 and does not hold it (it holds a contradictory belief B2), it will choose a causative action that, according to its current theory, could realize belief B1, i.e flip from holding a contradictory belief B2 to holding belief B1.

If a GM holds an opinion belief B1 it is not `confident` about, it will choose a causative action A1, if there is one, such that, according to the GM's theory, action A1 causes contradictory belief B2 to flip to B1 but not vice-versa.

If a GM has insufficient evidence whether an action A1 in its repertoire affects belief B1, it can choose action A1 to gather such evidence. A GM experiments to avoid bulding a disparity of evidence within its repertoire of actions.

If an action has been taken in round N to affect or test belief B1, no other action known to alter belief B1 should be taken, in this or other rounds, until it is affected, or until round N + I has completed (i.e. give it time). This is meant to keep a GM from "thrashing".

# Confidence in a belief

A GM is `confident` in a belief if it was verified recently (in the last N rounds) while being continuously held, and it will not repeatedly take action to verify it. This is meant to avoid OCD-like behaviors.

A GM's confidence in an opinion belief B1 is greatest right after it has been verified (by trying to test it via some action). 

A GM's confidence in an opinion belief B2 is given to a prediction error raised by the GM about B1 (predicted by a parent GM) if B1 contradicts B2.

A GM's confidence in an opinion belief B1 is given to the predictions it makes from that belief (predictions about inferred child GM beliefs B2, B3).

If a GM's confidence in opinion belief B1 is greater than the confidence of child GMs in related prediction errors, the GM dismisses the prediction errors and retains its belief B1, and it decreases its confidence in B1 by the maximum confidence in any of the prediction errors.

# The GM's theory (of itself in its environment) as generated logic program 

The logic program makes static and causal inferences.
  * Static: 
    * Perceptions => Beliefs
      * forward inferences: the GM infers current beliefs from its current and prior perceptions, 
      * backward inferences: the GM infers near-future perceptions, i.e. predictions on child GM beliefs, from its own near-future beliefs caused by actions
  * Causal: 
    * Beliefs x Actions =~> Beliefs
      * backward: the GM infers which actions would cause beliefs in the near-future
      * forward: the GM infers near-future beliefs from actions taken in this round

Infered beliefs can be about known objects (self, other) and about "hidden", i.e. abduced, objects in the GM's environment.

See Andy Karma notes for details.

# Andy Rover's defined frame

Types: robot, food, obstacle
Objects: self (a robot), other (a robot).

Each GM defines:
  * predicates (to express beliefs about objects)
  * constraints (on predicates)
  * static rules
  * causal rules

# Generating a theory-as-logic-program

A GM (re)generates a logic program from the data in past rounds that

* infers a GM's beliefs from its perceptions
* infers a GM's predictions (next beliefs of child GMs) from current beliefs and past perceptions
* infers a GM's actions from received predicted beliefs and current beliefs

## Challenges

The Apperception Engine was developed under assumptions that are not true of GMs, namely:

* Because GMs runs asynchronously and contribute to the perceptions of other GMs, any effects of an action taken at the end of round N may not be perceived by it during round N + 1 but only at round N + 2 or later.
* An action is taken with an outcome in mind: either realize an identified belief (goal, opinion) or realize a mutually exclusive belief (opinion).
* If a GM has a repertoire of actions at its disposal to achieve/verify beliefs, it wants to infer from experience which ones 






