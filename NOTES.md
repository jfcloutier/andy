Starting a SWI-PROLOG Pengine server

    > cd pengines-master
    > swipl
    ?- [load].
    ?- server(3030).

    Point browser to http://localhost:3030/ 
    login at user = "admin", password = "andy" - include the "!


Accessing the SWI-PROLOG pengine

    # Create a pengine on an application. Keep it alive.
    iex> {{:ok, {pid, id}}, other} = :pengine_master.create_pengine('http://localhost:3030/pengine', %{application: 'genealogist', destroy: false})

    # List of current pengines
    iex> [{pid, id}] = :pengine_master.list_pengines()

    # This will assert safely
    iex> {:success, id, [%{}], false} = :pengine.ask(pid, 'assert_father_child(jf, will)', %{})
    iex> {:success, id, [%{}], false} = :pengine.ask(pid, 'assert_father_child(liz, will)', %{})

    # Query and get one answer
    iex> {:success, id, answer, more_solutions?} = :pengine.ask(pid, 'ancestor_descendant(X, Y)', %{template: '[X, Y]', chunk: '1'})

    # Get next answer
    iex> {:success, id, answers, true = more_solutions?} = :pengine.next(pid)

    # Ran out of answers
    iex> {:failure, id} = :pengine.next(pid)

    # Bad query causes an error and stops the pengine
    iex> {:error, id, message_string, error_type_string} = :pengine.ask(pid, 'nonsense(X, [1,2, 3])', %{template: '[X]', chunk: '1'})

    # Terminate the pengine
    {:pengine_destroyed, _message} = :pengine.destroy(pid)

