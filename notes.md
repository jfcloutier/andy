# Meta-model

* A GM is an actor in the sense of the Actor Model
* A GM can have children GMs
* A GM can have multiple parent GMs
* GMs form an acyclic, parent-child directed graph with possibly multiple root nodes
* A GM defines a core set of conjectured beliefs. 
* A GM can abduce new beliefs via its evolving model. 
* Each belief belonging to at least one set (with > 1 members) of mutually exclusive beliefs.
  * Each such set identifies one default belief
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
  * A GM maintains a model (a generated logic program) it executes to 
    * update its beliefs when receiving prediction errors,
    * make predictions when its beliefs change
    * select actions to realize predicted goal beliefs and prove wrong predicted opinion beliefs
  * When starting up, a GM:
    * Accepts buffered, relevant predictions from parent GMs and prediction errors from child GMs emitted while it was not listening
    * Complete the set of held beliefs
  * When listening, it:
      * Receives and processes belief predictions from parent GMs, and prediction errors from child GMs
      * It completes this phase after a set amount of time has elapsed since the GM has emitted any prediction in this round
        * Each GM may have 
  * When acting, it:
    * Selects actions expected to achieve goal beliefs and invalidate opinion beliefs predicted in this round
    * Carry out these actions
  * When shutting down, it:
    * Commits the round to memory
    * Drops from memory rounds from too long ago
    * Triggers update of its model to be consistent with all remembered rounds

# Goal vs opinion beliefs

A GM gets goal and (default) opinion beliefs top-down from parent GMs (the parents mark the belief as goal or opinion). 

The GM validates its beliefs by predicting consequent perceptions (predicted beliefs of child GMs) and compiling prediction errors from child GMs. If one of its currently held beliefs is contradicted, the GM raises a prediction error to be captured by parent GMs.

The essential differences between a goal and an opinion belief are:

* A GM is expected to select and execute actions (to act) so as to *realize* a goal belief, i.e. made it valid
* A GM is expected to act to *test* an opinion belief, i.e. to make it valid or  invalid (both are equally desirable)

"If I am hungry then I predict that I am eating" (goal)
"If I am over food then I predict that I see white under me" (opinion)

In effect, the goal vs. opinion nature of the predicted belief contrains the choice of actions; to attempt making it true if it's a goal, or to attempt making it false if it's an opinion.

# Which actions to take

A GM has a repertoire, possibly empty, of potential actions (valued intents).

An action can be either `reactive` or `causative`.

A reactive action is statically associated with a belief B1 and is to be taken when a belief B1 is held after a contradictory belief B2 was held.

A causative action is to be taken to achieve belief B1. It is dynamically associated with belief B1 from experience by the model (logic program) of the GM.

If a GM holds an opinion belief, it will choose a causative action, if there is one, for which there is evidence that it causes a contradictory belief.

If a GM was predicted to hold a goal belief B1 and does not hold it (it holds a contradictory belief B2), it will choose a causative action, if there is one, for which there is evidence that it can realize belief B1.

There is evidence that action A1 causes belief B1 if it
  * is taken in round N where a belief B2 contradicting B1 is held and B1 is held in round N + I, where I < 3

If an action has been taken in round N to affect belief B1, no other action known to affect belief B1 should be taken, in this or other rounds, until it is affected, or until round N + I has completed (i.e. give it time). A GM avoids "thrashing".

If a GM has insufficient evidence whether an action A1 in its repertoire affects belief B1, it can choose action A1 to gather such evidence. A GM experiments. A GM should avoid bulding a disparity of evidence within its repertoire of actions (i.e. avoid narrow-mindedness).

# The model as generated logic program 

The logic program makes static and causal inferences.
  * Static: 
    * Perceptions => Beliefs
      * forward: the GM infers current beliefs from its current and prior perceptions, 
      * backward: the GM infers near-future perceptions, i.e. predictions, from near-future beliefs (caused by actions)
  * Causal: 
    * Beliefs x Actions =~> Beliefs
      * backward: the GM infers which actions will cause targeted changes in its beliefs in a near-future round
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

# Generating a model-as-logic-program

A GM (re)generates a logic program from the data in past rounds that

* infers a GM's beliefs from its perceptions
* infers a GM's predictions (next beliefs of child GMs) from current beliefs and past perceptions
* infers a GM's actions from received predicted beliefs and current beliefs

## Challenges

The Apperception Engine was developed under assumptions that are not true of GMs, namely:

* Because GMs runs asynchronously and contribute to the perceptions of other GMs, any effects of an action taken at the end of round N may not be perceived by it during round N + 1 but only at round N + 2 or later.
* An action is taken with an outcome in mind: either realize an identified belief (goal, opinion) or realize a mutually exclusive belief (opinion).
* If a GM has a repertoire of actions at its disposal to achieve/verify beliefs, it wants to infer from experience which ones 






