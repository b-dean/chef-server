%% -*- erlang-indent-level: 4;indent-tabs-mode: nil; fill-column: 92-*-
%% ex: ts=4 sw=4 et

-module(heimdall_db).

-include("heimdall.hrl").

-export([acl_membership/4,
         add_to_group/3,
         create/3,
         delete/2,
         delete_acl/3,
         exists/2,
         group_membership/2,
         has_permission/4,
         remove_from_group/3,
         statements/0,
         update_acl/5]).

-spec create(auth_type(), auth_id(), auth_id() | null) ->
                    ok | {conflict, term()} | {error, term()}.
create(Type, AuthzId, RequestorId) when RequestorId =:= superuser orelse
                                        RequestorId =:= undefined ->
    create(Type, AuthzId, null);
create(Type, AuthzId, RequestorId) ->
    case sqerl:select(create_entity, [Type, AuthzId, RequestorId],
                      first_as_scalar, [success]) of
        {ok, true} ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.


delete_stmt(actor)     -> delete_actor_by_authz_id;
delete_stmt(container) -> delete_container_by_authz_id;
delete_stmt(group)     -> delete_group_by_authz_id;
delete_stmt(object)    -> delete_object_by_authz_id.

-spec delete(auth_type(), auth_id()) -> ok | {error, term()}.
delete(Type, AuthzId) ->
    DeleteStatement = delete_stmt(Type),
    case sqerl:statement(DeleteStatement, [AuthzId], count) of
        {ok, 1} ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

exists_query(actor)     -> actor_exists;
exists_query(container) -> container_exists;
exists_query(group)     -> group_exists;
exists_query(object)    -> object_exists.

-spec exists(auth_type(), auth_id()) -> boolean().
exists(Type, AuthId) ->
    StatementName = exists_query(Type),
    {ok, Answer} = sqerl:select(StatementName, [AuthId], first_as_scalar, [exists]),
    Answer.

acl_member_query(actor, actor) -> actors_in_actor_acl;
acl_member_query(group, actor) -> groups_in_actor_acl;
acl_member_query(actor, group) -> actors_in_group_acl;
acl_member_query(group, group) -> groups_in_group_acl;
acl_member_query(actor, object) -> actors_in_object_acl;
acl_member_query(group, object) -> groups_in_object_acl;
acl_member_query(actor, container) -> actors_in_container_acl;
acl_member_query(group, container) -> groups_in_container_acl.

-spec acl_membership(auth_type(), auth_type(), auth_id(), permission()) ->
                              list() | {error, term()}.
acl_membership(TargetType, AuthorizeeType, AuthzId, Permission) ->
    MembershipStatement = acl_member_query(AuthorizeeType, TargetType),
    case sqerl:select(MembershipStatement, [AuthzId, Permission], rows_as_scalars,
                      [authz_id]) of
        {ok, L} when is_list(L) ->
            L;
        {ok, none} ->
            [];
        {error, Error} ->
            {error, Error}
    end.

sql_array(List) ->
    List0 = [binary_to_list(X) || X <- List],
    string:join(List0, ",").

-spec update_acl(auth_type(), auth_id(), permission(), list(), list()) ->
                        ok | {error, term()}.
update_acl(TargetType, TargetId, Permission, Actors, Groups) ->
    case sqerl:select(update_acl, [TargetType, TargetId, Permission,
                                   sql_array(Actors), sql_array(Groups)],
                      first_as_scalar, [success]) of
        {ok, true} ->
            ok;
        {not_null_violation, _Reason} ->
            {error, null_violation};
        {error, Reason} ->
            {error, Reason}
    end.

-spec delete_acl(auth_type(), auth_id(), permission()) -> ok | {error, term()}.
delete_acl(TargetType, TargetId, Permission) ->
    case sqerl:select(clear_acl, [TargetType, TargetId, Permission],
                      first_as_scalar, [success]) of
        {ok, true} ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

-spec has_permission(auth_type(), auth_id(), auth_id(), permission() | any) -> boolean().
has_permission(TargetType, TargetId, RequestorId, Permission) ->
    case sqerl:select(actor_has_permission_on, [RequestorId, TargetId, TargetType,
                                                Permission],
                      first_as_scalar, [permission]) of
        {ok, Answer} ->
            Answer;
        {not_null_violation, _Error} ->
            % If this fails because the target doesn't exist, can't have permission
            false;
        {error, Error} ->
            {error, Error}
    end.

membership_query(actor) -> group_actor_members;
membership_query(group) -> group_group_members.

-spec group_membership(auth_type(), auth_id()) -> list() | {error, term()}.
group_membership(TargetType, GroupId) ->
    MembershipStatement = membership_query(TargetType),
    case sqerl:select(MembershipStatement, [GroupId], rows_as_scalars,
                      [authz_id]) of
        {ok, L} when is_list(L) ->
            L;
        {ok, none} ->
            [];
        {error, Error} ->
            {error, Error}
    end.

group_insert_stmt(actor)     -> insert_actor_into_group;
group_insert_stmt(group)     -> insert_group_into_group.

-spec add_to_group(auth_type(), auth_id(), auth_id()) -> ok | {error, term()}.
add_to_group(Type, MemberId, GroupId) ->
    InsertStatement = group_insert_stmt(Type),
    case sqerl:statement(InsertStatement, [MemberId, GroupId], count) of
        {ok, 1} ->
            ok;
        {conflict, _Reason} ->
            % Already in group, nothing to do here
            ok;
        {group_cycle, _Reason} ->
            {error, group_cycle};
        {check_violation, _Reason} ->
            {error, group_cycle};
        {not_null_violation, _Reason} ->
            {error, null_violation};
        {error, Reason} ->
            {error, Reason}
    end.

group_remove_stmt(actor)     -> delete_actor_from_group;
group_remove_stmt(group)     -> delete_group_from_group.

-spec remove_from_group(auth_type(), auth_id(), auth_id()) -> ok | {error, term()}.
remove_from_group(Type, MemberId, GroupId) ->
    DeleteStatement = group_remove_stmt(Type),
    case sqerl:statement(DeleteStatement, [MemberId, GroupId], count) of
        {ok, 1} ->
            ok;
        {ok, none} ->
            {error, not_found_in_group};
        {error, Reason} ->
            {error, Reason}
    end.

statements() ->
    Path = filename:join([code:priv_dir(heimdall), "pgsql_statements.config"]),
    {ok, Statements} = file:consult(Path),
    Statements.
