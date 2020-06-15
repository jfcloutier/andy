Starting a SWI-PROLOG Pengine server

    > cd pengines-master
    > swipl
    ?- [load].
    ?- server(3030).

    Point browser to http://localhost:3030/ 
    login at user = "admin", password = "andy" - include the "!


Accessing the SWI-PROLOG pengine

    iex> {{:ok, {pid, id}}, other} = :pengine_master.create_pengine('http://localhost:3030/pengine', %{})

    iex> [{pid, id}] = :pengine_master.list_pengines()

    iex> {:success, id, answer, more_solutions?} = :pengine.ask(pid, 'member(X, [1,2, 3])', %{template: '[X]', chunk: '1'})

    iex> {:success, id, answers, more_solutions?} = :pengine.next(pid)

    iex> {{:success, id, answers, more_solutions?}, status} = :pengine.next(pid)

    iex> {:error, id, message_string, error_type_string} = :pengine.ask(pid, 'nonsense(X, [1,2, 3])', %{template: '[X]', chunk: '1'})

