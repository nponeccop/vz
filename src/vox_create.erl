-module(vox_create).
-compile(export_all).

command(Args) -> vox:info("~p Args: ~p~n",[?MODULE,Args]), {ok2,?MODULE}.
