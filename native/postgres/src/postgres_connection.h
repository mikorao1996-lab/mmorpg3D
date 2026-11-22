#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include <libpq-fe.h>

#include <mutex>

class PostgresConnection : public godot::RefCounted {
	GDCLASS(PostgresConnection, godot::RefCounted)

	mutable std::mutex mutex;
	PGconn *connection = nullptr;
	bool transaction_open = false;

	static void _bind_methods();
	godot::Dictionary execute_query_locked(const godot::String &p_query, const godot::Array &p_params);
	void close_connection_locked();

public:
	~PostgresConnection() override;

	godot::Dictionary connect_to_db(
			const godot::String &p_host,
			int p_port,
			const godot::String &p_database,
			const godot::String &p_user,
			const godot::String &p_password);
	godot::Dictionary execute_query(const godot::String &p_query, const godot::Array &p_params = godot::Array());
	godot::Dictionary begin_transaction();
	godot::Dictionary commit_transaction();
	godot::Dictionary rollback_transaction();
	void close_connection();
	bool is_connected() const;
};
