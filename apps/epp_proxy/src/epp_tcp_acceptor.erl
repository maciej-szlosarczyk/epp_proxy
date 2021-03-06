%% This is a test module for local development only. TCP without TLS is
%% against the EPP specification, it should not be used in production.
%%
%% This gen_server is only deployed if dev_mode property on epp_proxy app is set
%% to true.
-module(epp_tcp_acceptor).

-behaviour(gen_server).

-define(SERVER, ?MODULE).

-define(POOL_SUPERVISOR, epp_pool_supervisor).

-define(WORKER, epp_tcp_worker).

%% gen_server callbacks
-export([handle_call/3, handle_cast/2, init/1,
	 start_link/1]).

-record(state, {socket, port, options}).

start_link(Port) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Port,
			  []).

init(Port) ->
    Options = [binary, {packet, raw}, {active, false},
	       {reuseaddr, true}],
    {ok, ListenSocket} = gen_tcp:listen(Port, Options),
    gen_server:cast(self(), accept),
    {ok,
     #state{socket = ListenSocket, port = Port,
	    options = Options}}.

handle_cast(accept,
	    State = #state{socket = ListenSocket, port = Port,
			   options = Options}) ->
    {ok, AcceptSocket} = gen_tcp:accept(ListenSocket),
    {ok, NewOwner} = create_worker(AcceptSocket),
    ok = gen_tcp:controlling_process(AcceptSocket,
				     NewOwner),
    gen_server:cast(NewOwner, serve),
    gen_server:cast(NewOwner, greeting),
    gen_server:cast(self(), accept),
    {noreply,
     State#state{socket = ListenSocket, port = Port,
		 options = Options}}.

handle_call(_E, _From, State) -> {noreply, State}.

create_worker(Socket) ->
    ChildSpec = #{id => rand:uniform(), type => worker,
		  modules => [?WORKER], restart => temporary,
		  start => {?WORKER, start_link, [Socket]}},
    supervisor:start_child(?POOL_SUPERVISOR, ChildSpec).
