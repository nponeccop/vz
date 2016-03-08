-module(vox_start).
-compile(export_all).

command(Args) -> {ok,lists:map(fun start/1,Args)}.

start(App) ->
    vox:info("App: ~p~n",[App]),
    Dir       = filename:join(["apps", App]),
    {ok,Bin}  = file:read_file(filename:join([Dir, "config.json"])),
    {Json   } = jsone:decode(Bin),
    {Process} = proplists:get_value(<<"process">>,Json),
    Args      = proplists:get_value(<<"args">>,Process),
    {User}    = proplists:get_value(<<"user">>,Process),
    Uid       = proplists:get_value(<<"uid">>,User,0),
    Gid       = proplists:get_value(<<"gid">>,User,0),
    UserSpec  = lists:flatten(io_lib:format("--userspec=~p:~p", [Uid,Gid])),
    Concat    = ["chroot",UserSpec,"rootfs"] ++ lists:map(fun(X) -> binary_to_list(X) end,Args),
    vox:info("Oneliner: ~p~n",[Concat]),
    {_,R,S}   = sh:run(Concat,<<"log">>,Dir),
    {ret(R),S}.

ret(0) -> ok;
ret(_) -> error.
