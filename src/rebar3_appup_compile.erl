%% -------------------------------------------------------------------
%%
%% Copyright (c) 2016 Luis Rascão.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------
-module(rebar3_appup_compile).

-export([init/1,
         do/1,
         format_error/1]).

-define(PROVIDER, compile).
-define(DEPS, [{default, app_discovery}]).

%% ===================================================================
%% Public API
%% ===================================================================
-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    Provider = providers:create([
            {name, ?PROVIDER},            % The 'user friendly' name of the task
            {namespace, appup},
            {module, ?MODULE},            % The module implementation of the task
            {bare, true},                 % The task can be run by the user, always true
            {deps, ?DEPS},                % The list of dependencies
            {opts, []},                   % list of options understood by the plugin
            {example, "rebar3 appup compile"},
            {short_desc, "Compile and validate all .appup.src files"},
            {desc, "Appup compile"}
    ]),
    {ok, rebar_state:add_provider(State, Provider)}.

-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, string()}.
do(State) ->
    Apps = case rebar_state:current_app(State) of
            undefined ->
                rebar_state:project_apps(State);
            AppInfo ->
                [AppInfo]
           end,
    lists:foreach(fun(AppInfo) ->
                    Opts = rebar_app_info:opts(AppInfo),
                    Source = appup_file_src(AppInfo),
                    case filelib:is_file(Source) of
                        true ->
                            rebar_api:info("Compiling ~s",
                                [filename:basename(Source)]),
                            Target = appup_file_target(AppInfo),
                            {ok, AppupTerm} = evaluate(Source),
                            compile(AppupTerm, Target, Opts);
                        false -> ok
                    end
                  end, Apps),
    {ok, State}.

-spec format_error(any()) ->  iolist().
format_error(Reason) ->
    io_lib:format("~p", [Reason]).

%% ===================================================================
%% Private API
%% ===================================================================
-type bs_vars() :: [{term(), term()}].
-spec bs(bs_vars()) -> bs_vars().
bs(Vars) ->
    lists:foldl(fun({K,V}, Bs) ->
                        erl_eval:add_binding(K, V, Bs)
                end, erl_eval:new_bindings(), Vars).

evaluate(Source) ->
    file:script(Source, bs([])).

compile(AppupTerm, Target, _Opts) ->
    %% Perform basic validation on the appup file
    %% i.e. if a consult succeeds and basic appup
    %% structure exists.
    case AppupTerm of
        %% The .appup syntax is described in
        %% http://erlang.org/doc/man/appup.html.
        {_Vsn, UpFromVsn, DownToVsn}
          when is_list(UpFromVsn), is_list(DownToVsn) ->
            case file:write_file(
                   Target,
                   lists:flatten(io_lib:format("~p.", [AppupTerm]))) of
                {error, Reason} ->
                    rebar_api:abort("Failed writing to target file ~s due to ~s",
                           [Target, Reason]);
                ok ->
                    ok
            end;
        _ ->
            rebar_api:abort("Failed to compile not an appup:\n~p~n",
                [AppupTerm])
    end.

appup_file_src(AppInfo) ->
    Dir = rebar_app_info:dir(AppInfo),
    Name = rebar_app_info:name(AppInfo),
    filename:join([Dir, "src", ec_cnv:to_list(Name) ++ ".appup.src"]).

appup_file_target(AppInfo) ->
    OutDir = rebar_app_info:ebin_dir(AppInfo),
    Name = rebar_app_info:name(AppInfo),
    filename:join(OutDir, ec_cnv:to_list(Name) ++ ".appup").