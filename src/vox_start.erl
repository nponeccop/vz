-module(vox_start).
-compile(export_all).

command(A) ->
    {ok,Bin}  = file:read_file("apps/busybox/config.json"),
    {Json   } = jsone:decode(Bin),
    {Process} = proplists:get_value(<<"process">>,Json),
    Args      = proplists:get_value(<<"args">>,Process),
    Concat    = string:join(lists:map(fun(X) -> binary_to_list(X) end,Args)," "),
    Oneliner  = lists:concat(["cd apps/busybox; sudo ",Concat]),
    {_,R,S}   = sh:oneliner(Oneliner),
    vox:info("Oneliner: ~p~n",[Oneliner]),
    {ret(R),S}.

ret(0) -> ok;
ret(_) -> error.
