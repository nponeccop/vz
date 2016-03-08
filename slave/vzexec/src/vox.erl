-module(vox).
-author('Andy Melnikov').
-include("vox.hrl").
-compile(export_all).
-export([main/1]).

main([]) -> help();
main(Params) ->
    {Other,FP} = fold_params(Params),
    unknown(Other),
    return(errors(lists:flatten(lists:foldl(fun (_,Errors) when length(Errors) > 0 -> Errors;
                                  ({Name,Par},Errors) -> [return(Name:command(Par))|Errors] end, [], FP)))).

unknown([])    -> skip;
unknown(Other) -> info("Unknown Command or Parameter ~p~n",[Other]), help().

errors(L)    when length(L) == 0 -> false;
errors(L)      -> info("Errors: ~p~n",[L]), true.

return(true)   -> 1;
return(false)  -> 0;
return({ok,L}) -> info("Command: ~p~n",[L]), [];
return(X)      -> X.

help(Reason, Data) -> help(io_lib:format("~s ~p", [Reason, Data])).
help(Msg) -> info("Error: ~s~n~n", [Msg]), help().
help()    -> info("VOX Container Tool version ~s~n",[?VERSION]),
             info("BNF: ~n"),
             info("    invoke := vox params~n"),
             info("    params := [] | run params ~n"),
             info("       run := command [ options ]~n"),
             info("   command := create [container.tgz] | start | stop~n"),
             return(false).

info(Format)      -> io:format(lists:concat([Format,"\r"])).
info(Format,Args) -> io:format(lists:concat([Format,"\r"]),Args).

plugin(X)         -> plugin(X,lists:member(list_to_atom(X),plugins())).
plugin(X,true)    -> list_to_atom(lists:concat(['vox_',X]));
plugin(X,false)   -> X.

plugins()         -> application:get_env(vox,plugins,[create,start,stop]).
plugins([],N)     -> N;
plugins([H|T],N)  -> plugins(T,[plugin(H)|N]).

fold_params(Params) ->
   Atomized = plugins(Params,[]),
   lists:foldl(fun(X,{Current,Result}) ->
      case X of
           X when is_atom(X) -> {[],[{X,Current}|Result]};
           E -> {[E|Current],Result} end
      end, {[],[]}, Atomized).
