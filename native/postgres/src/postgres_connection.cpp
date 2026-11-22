#include "postgres_connection.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/char_string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cmath>
#include <cstdlib>
#include <iomanip>
#include <limits>
#include <locale>
#include <sstream>
#include <string>
#include <vector>

using namespace godot;

namespace {

Dictionary make_error_response(const String &p_error) {
	Dictionary response;
	response["ok"] = false;
	response["error"] = p_error;
	response["rows"] = Array();
	response["affected_rows"] = int64_t(0);
	response["command"] = String();
	return response;
}

bool encode_string(const String &p_value, std::string &r_encoded) {
	const CharString utf8 = p_value.utf8();
	r_encoded.assign(utf8.get_data(), static_cast<size_t>(utf8.length()));
	return r_encoded.find('\0') == std::string::npos;
}

bool encode_parameter(const Variant &p_value, std::string &r_encoded, bool &r_is_null) {
	r_is_null = false;

	switch (p_value.get_type()) {
		case Variant::NIL:
			r_is_null = true;
			r_encoded.clear();
			return true;
		case Variant::BOOL:
			r_encoded = p_value.operator bool() ? "true" : "false";
			return true;
		case Variant::INT:
			r_encoded = std::to_string(p_value.operator int64_t());
			return true;
		case Variant::FLOAT: {
			const double value = p_value.operator double();
			if (std::isnan(value)) {
				r_encoded = "NaN";
			} else if (std::isinf(value)) {
				r_encoded = std::signbit(value) ? "-Infinity" : "Infinity";
			} else {
				std::ostringstream stream;
				stream.imbue(std::locale::classic());
				stream << std::setprecision(std::numeric_limits<double>::max_digits10) << value;
				r_encoded = stream.str();
			}
			return true;
		}
		case Variant::STRING:
			return encode_string(p_value.operator String(), r_encoded);
		default:
			return false;
	}
}

} // namespace

void PostgresConnection::_bind_methods() {
	ClassDB::bind_method(
			D_METHOD("connect_to_db", "host", "port", "database", "user", "password"),
			&PostgresConnection::connect_to_db);
	ClassDB::bind_method(
			D_METHOD("execute_query", "query", "params"),
			&PostgresConnection::execute_query,
			DEFVAL(Array()));
	ClassDB::bind_method(D_METHOD("begin_transaction"), &PostgresConnection::begin_transaction);
	ClassDB::bind_method(D_METHOD("commit_transaction"), &PostgresConnection::commit_transaction);
	ClassDB::bind_method(D_METHOD("rollback_transaction"), &PostgresConnection::rollback_transaction);
	ClassDB::bind_method(D_METHOD("close_connection"), &PostgresConnection::close_connection);
	ClassDB::bind_method(D_METHOD("is_connected"), &PostgresConnection::is_connected);
}

PostgresConnection::~PostgresConnection() {
	close_connection_locked();
}

Dictionary PostgresConnection::connect_to_db(
		const String &p_host,
		int p_port,
		const String &p_database,
		const String &p_user,
		const String &p_password) {
	std::lock_guard<std::mutex> lock(mutex);
	close_connection_locked();

	if (p_port < 1 || p_port > 65535) {
		return make_error_response("PostgreSQL port must be between 1 and 65535.");
	}
	if (p_database.is_empty() || p_user.is_empty()) {
		return make_error_response("PostgreSQL database and user must not be empty.");
	}

	std::string host;
	std::string database;
	std::string user;
	std::string password;
	if (!encode_string(p_host, host) ||
			!encode_string(p_database, database) ||
			!encode_string(p_user, user) ||
			!encode_string(p_password, password)) {
		return make_error_response("PostgreSQL connection values must not contain NUL bytes.");
	}

	const std::string port = std::to_string(p_port);
	const char *keywords[] = {
		"host",
		"port",
		"dbname",
		"user",
		"password",
		"connect_timeout",
		nullptr,
	};
	const char *values[] = {
		host.c_str(),
		port.c_str(),
		database.c_str(),
		user.c_str(),
		password.c_str(),
		"5",
		nullptr,
	};

	PGconn *new_connection = PQconnectdbParams(keywords, values, 0);
	if (new_connection == nullptr) {
		return make_error_response("libpq could not allocate a PostgreSQL connection.");
	}
	if (PQstatus(new_connection) != CONNECTION_OK) {
		const char *message = PQerrorMessage(new_connection);
		const String error = message == nullptr || message[0] == '\0'
				? String("PostgreSQL connection failed.")
				: String::utf8(message);
		PQfinish(new_connection);
		return make_error_response(error);
	}

	connection = new_connection;
	Dictionary response;
	response["ok"] = true;
	response["error"] = String();
	response["rows"] = Array();
	response["affected_rows"] = int64_t(0);
	response["command"] = String();
	return response;
}

Dictionary PostgresConnection::execute_query(const String &p_query, const Array &p_params) {
	std::lock_guard<std::mutex> lock(mutex);
	return execute_query_locked(p_query, p_params);
}

Dictionary PostgresConnection::execute_query_locked(const String &p_query, const Array &p_params) {
	if (connection == nullptr || PQstatus(connection) != CONNECTION_OK) {
		return make_error_response("Not connected to PostgreSQL.");
	}
	if (p_params.size() > std::numeric_limits<int>::max()) {
		return make_error_response("Too many PostgreSQL query parameters.");
	}

	std::vector<std::string> encoded_params;
	std::vector<bool> null_params;
	encoded_params.reserve(static_cast<size_t>(p_params.size()));
	null_params.reserve(static_cast<size_t>(p_params.size()));

	for (int64_t index = 0; index < p_params.size(); ++index) {
		std::string encoded;
		bool is_null = false;
		if (!encode_parameter(p_params[index], encoded, is_null)) {
			return make_error_response(
					"Unsupported PostgreSQL parameter type or a parameter containing a NUL byte.");
		}
		encoded_params.push_back(std::move(encoded));
		null_params.push_back(is_null);
	}

	std::vector<const char *> parameter_values;
	parameter_values.reserve(encoded_params.size());
	for (size_t index = 0; index < encoded_params.size(); ++index) {
		parameter_values.push_back(null_params[index] ? nullptr : encoded_params[index].c_str());
	}

	const CharString query = p_query.utf8();
	if (std::string(query.get_data(), static_cast<size_t>(query.length())).find('\0') != std::string::npos) {
		return make_error_response("PostgreSQL query must not contain NUL bytes.");
	}

	PGresult *query_result = PQexecParams(
			connection,
			query.get_data(),
			static_cast<int>(parameter_values.size()),
			nullptr,
			parameter_values.empty() ? nullptr : parameter_values.data(),
			nullptr,
			nullptr,
			0);
	if (query_result == nullptr) {
		const char *message = PQerrorMessage(connection);
		return make_error_response(message == nullptr || message[0] == '\0'
				? String("PostgreSQL query failed.")
				: String::utf8(message));
	}

	const ExecStatusType status = PQresultStatus(query_result);
	if (status != PGRES_COMMAND_OK && status != PGRES_TUPLES_OK) {
		const char *message = PQresultErrorMessage(query_result);
		const String error = message == nullptr || message[0] == '\0'
				? String("PostgreSQL returned an unsuccessful query status.")
				: String::utf8(message);
		PQclear(query_result);
		return make_error_response(error);
	}

	Array rows;
	const int row_count = PQntuples(query_result);
	const int field_count = PQnfields(query_result);
	for (int row_index = 0; row_index < row_count; ++row_index) {
		Dictionary row;
		for (int field_index = 0; field_index < field_count; ++field_index) {
			const char *field_name = PQfname(query_result, field_index);
			const String key = field_name == nullptr ? String() : String::utf8(field_name);
			if (PQgetisnull(query_result, row_index, field_index)) {
				row[key] = Variant();
			} else {
				row[key] = String::utf8(
						PQgetvalue(query_result, row_index, field_index),
						PQgetlength(query_result, row_index, field_index));
			}
		}
		rows.append(row);
	}

	const char *affected_rows_text = PQcmdTuples(query_result);
	const int64_t affected_rows = affected_rows_text == nullptr || affected_rows_text[0] == '\0'
			? int64_t(0)
			: static_cast<int64_t>(std::strtoll(affected_rows_text, nullptr, 10));
	const char *command_text = PQcmdStatus(query_result);
	const String command = command_text == nullptr ? String() : String::utf8(command_text);
	PQclear(query_result);

	Dictionary response;
	response["ok"] = true;
	response["error"] = String();
	response["rows"] = rows;
	response["affected_rows"] = affected_rows;
	response["command"] = command;
	return response;
}

Dictionary PostgresConnection::begin_transaction() {
	std::lock_guard<std::mutex> lock(mutex);
	if (transaction_open) {
		return make_error_response("A PostgreSQL transaction is already open.");
	}

	Dictionary response = execute_query_locked("BEGIN", Array());
	if (bool(response["ok"])) {
		transaction_open = true;
	}
	return response;
}

Dictionary PostgresConnection::commit_transaction() {
	std::lock_guard<std::mutex> lock(mutex);
	if (!transaction_open) {
		return make_error_response("No PostgreSQL transaction is open.");
	}

	Dictionary response = execute_query_locked("COMMIT", Array());
	if (!bool(response["ok"])) {
		return response;
	}

	transaction_open = false;
	const String command = response["command"];
	if (command != "COMMIT") {
		return make_error_response("PostgreSQL did not commit the transaction.");
	}
	return response;
}

Dictionary PostgresConnection::rollback_transaction() {
	std::lock_guard<std::mutex> lock(mutex);
	if (!transaction_open) {
		return make_error_response("No PostgreSQL transaction is open.");
	}

	Dictionary response = execute_query_locked("ROLLBACK", Array());
	if (!bool(response["ok"])) {
		return response;
	}

	transaction_open = false;
	const String command = response["command"];
	if (command != "ROLLBACK") {
		return make_error_response("PostgreSQL did not roll back the transaction.");
	}
	return response;
}

void PostgresConnection::close_connection_locked() {
	if (connection != nullptr) {
		PQfinish(connection);
		connection = nullptr;
	}
	transaction_open = false;
}

void PostgresConnection::close_connection() {
	std::lock_guard<std::mutex> lock(mutex);
	close_connection_locked();
}

bool PostgresConnection::is_connected() const {
	std::lock_guard<std::mutex> lock(mutex);
	return connection != nullptr && PQstatus(connection) == CONNECTION_OK;
}
