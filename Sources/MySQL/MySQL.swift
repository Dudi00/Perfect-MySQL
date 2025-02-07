//
//  MySQL.swift
//  MySQL
//
//  Created by Kyle Jessup on 2015-10-01.
//	Copyright (C) 2015 PerfectlySoft, Inc.
//
//===----------------------------------------------------------------------===//
//
// This source file is part of the Perfect.org open source project
//
// Copyright (c) 2015 - 2016 PerfectlySoft Inc. and the Perfect project authors
// Licensed under Apache License v2.0
//
// See http://perfect.org/licensing.html for license information
//
//===----------------------------------------------------------------------===//
//

#if os(Linux)
	import SwiftGlibc
#else
	import Darwin
#endif
import mysqlclient

#if swift(>=3.0)
	extension UnsafeMutablePointer {
		public static func alloc(num: Int) -> UnsafeMutablePointer<Pointee> {
			return UnsafeMutablePointer<Pointee>.alloc(num)
		}
	}
#else
	typealias IteratorProtocol = GeneratorType
	typealias UnicodeCodec = UnicodeCodecType
	typealias Sequence = SequenceType
	
	extension String {
		init?(validatingUTF8: UnsafePointer<Int8>) {
			if let s = String.fromCString(validatingUTF8) {
				self.init(s)
			} else {
				return nil
			}
		}
	}
	extension UnsafeMutablePointer {
		
		var pointee: Memory {
			get { return self.memory }
			set { self.memory = newValue }
		}
		
		func deallocateCapacity(num: Int) {
			self.dealloc(num)
		}
		
		func advanced(by by: Int) -> UnsafeMutablePointer<Memory> {
			return self.advancedBy(by)
		}
		
		func deinitialize(count count: Int) {
			self.destroy(count)
		}
		
		func initialize(with newvalue: Memory) {
			self.initialize(newvalue)
		}
	}
#endif

/// This class permits an UnsafeMutablePointer to be used as a IteratorProtocol
struct GenerateFromPointer<T> : IteratorProtocol {
	
	typealias Element = T
	
	var count = 0
	var pos = 0
	var from: UnsafeMutablePointer<T>
	
	/// Initialize given an UnsafeMutablePointer and the number of elements pointed to.
	init(from: UnsafeMutablePointer<T>, count: Int) {
		self.from = from
		self.count = count
	}
	
	/// Return the next element or nil if the sequence has been exhausted.
	mutating func next() -> Element? {
		guard count > 0 else {
			return nil
		}
		self.count -= 1
		let result = self.from[self.pos]
		self.pos += 1
		return result
	}
}

/// A generalized wrapper around the Unicode codec operations.
struct Encoding {
	
	/// Return a String given a character generator.
	static func encode<D : UnicodeCodec, G : IteratorProtocol where G.Element == D.CodeUnit>(decoder : D, generator: G) -> String {
		var encodedString = ""
		var finished: Bool = false
		var mutableDecoder = decoder
		var mutableGenerator = generator
		repeat {
			let decodingResult = mutableDecoder.decode(&mutableGenerator)
			#if swift(>=3.0)
			switch decodingResult {
			case .scalarValue(let char):
				encodedString.append(char)
			case .emptyInput:
				finished = true
				/* ignore errors and unexpected values */
			case .error:
				finished = true
			}
			#else
			switch decodingResult {
			case .Result(let char):
				encodedString.append(char)
			case .EmptyInput:
				finished = true
				/* ignore errors and unexpected values */
			case .Error:
				finished = true
			}
			#endif
		} while !finished
		return encodedString
	}
}

/// Utility wrapper permitting a UTF-8 character generator to encode a String. Also permits a String to be converted into a UTF-8 byte array.
class UTF8Encoding {
	
	/// Use a character generator to create a String.
	static func encode<G : IteratorProtocol where G.Element == UTF8.CodeUnit>(generator: G) -> String {
		return Encoding.encode(UTF8(), generator: generator)
	}
	
	#if swift(>=3.0)
	/// Use a character sequence to create a String.
	static func encode<S : Sequence where S.Iterator.Element == UTF8.CodeUnit>(bytes: S) -> String {
		return encode(bytes.makeIterator())
	}
	#else
	/// Use a character sequence to create a String.
	static func encode<S : SequenceType where S.Generator.Element == UTF8.CodeUnit>(bytes: S) -> String {
		return encode(bytes.generate())
	}
	#endif

	/// Decode a String into an array of UInt8.
	static func decode(str: String) -> Array<UInt8> {
		return [UInt8](str.utf8)
	}
}

public enum MySQLOpt {
	case MYSQL_OPT_CONNECT_TIMEOUT, MYSQL_OPT_COMPRESS, MYSQL_OPT_NAMED_PIPE,
		MYSQL_INIT_COMMAND, MYSQL_READ_DEFAULT_FILE, MYSQL_READ_DEFAULT_GROUP,
		MYSQL_SET_CHARSET_DIR, MYSQL_SET_CHARSET_NAME, MYSQL_OPT_LOCAL_INFILE,
		MYSQL_OPT_PROTOCOL, MYSQL_SHARED_MEMORY_BASE_NAME, MYSQL_OPT_READ_TIMEOUT,
		MYSQL_OPT_WRITE_TIMEOUT, MYSQL_OPT_USE_RESULT,
		MYSQL_OPT_USE_REMOTE_CONNECTION, MYSQL_OPT_USE_EMBEDDED_CONNECTION,
		MYSQL_OPT_GUESS_CONNECTION, MYSQL_SET_CLIENT_IP, MYSQL_SECURE_AUTH,
		MYSQL_REPORT_DATA_TRUNCATION, MYSQL_OPT_RECONNECT,
		MYSQL_OPT_SSL_VERIFY_SERVER_CERT, MYSQL_PLUGIN_DIR, MYSQL_DEFAULT_AUTH,
		MYSQL_OPT_BIND,
		MYSQL_OPT_SSL_KEY, MYSQL_OPT_SSL_CERT,
		MYSQL_OPT_SSL_CA, MYSQL_OPT_SSL_CAPATH, MYSQL_OPT_SSL_CIPHER,
		MYSQL_OPT_SSL_CRL, MYSQL_OPT_SSL_CRLPATH,
		MYSQL_OPT_CONNECT_ATTR_RESET, MYSQL_OPT_CONNECT_ATTR_ADD,
		MYSQL_OPT_CONNECT_ATTR_DELETE,
		MYSQL_SERVER_PUBLIC_KEY,
		MYSQL_ENABLE_CLEARTEXT_PLUGIN,
		MYSQL_OPT_CAN_HANDLE_EXPIRED_PASSWORDS
}

public final class MySQL {
	
	static private var dispatchOnce = pthread_once_t()
	
	private var ptr: UnsafeMutablePointer<MYSQL>
	
	public static func clientInfo() -> String {
		return String(validatingUTF8: mysql_get_client_info()) ?? ""
	}
	
	public init() {
		
		pthread_once(&MySQL.dispatchOnce) {
			mysql_server_init(0, nil, nil)
		}
		
		self.ptr = mysql_init(nil)
	}
	
	deinit {
		self.close()
	}
	
	public func close() {
		if self.ptr != nil {
			mysql_close(self.ptr)
			self.ptr = nil
		}
	}
	
	public func errorCode() -> UInt32 {
		return mysql_errno(self.ptr)
	}
	
	public func errorMessage() -> String {
		return String(validatingUTF8: mysql_error(self.ptr)) ?? ""
	}
	
	public func serverVersion() -> Int {
		return Int(mysql_get_server_version(self.ptr))
	}
	
	// returns an allocated buffer holding the string's contents and the full size in bytes which was allocated
	// An empty (but not nil) string would have a count of 1
	static func convertString(s: String?) -> (UnsafeMutablePointer<Int8>, Int) {
		var ret: (UnsafeMutablePointer<Int8>, Int) = (UnsafeMutablePointer<Int8>(nil), 0)
		guard let notNilString = s else {
			return ret
		}
		notNilString.withCString { p in
			var c = 0
			while p[c] != 0 {
				c += 1
			}
			c += 1
			let alloced = UnsafeMutablePointer<Int8>.alloc(c)
			alloced.initialize(with: 0)
			for i in 0..<c {
				alloced[i] = p[i]
			}
			alloced[c-1] = 0
			ret = (alloced, c)
		}
		return ret
	}
	
	func cleanConvertedString(pair: (UnsafeMutablePointer<Int8>, Int)) {
		if pair.1 > 0 {
			pair.0.deinitialize(count: pair.1)
			pair.0.deallocateCapacity(pair.1)
		}
	}
	
	public func connect(host: String? = nil, user: String? = nil, password: String? = nil, db: String? = nil, port: UInt32 = 0, socket: String? = nil, flag: UInt = 0) -> Bool {
		if self.ptr == nil {
			self.ptr = mysql_init(nil)
		}
		
		let hostOrBlank = MySQL.convertString(host)
		let userOrBlank = MySQL.convertString(user)
		let passwordOrBlank = MySQL.convertString(password)
		let dbOrBlank = MySQL.convertString(db)
		let socketOrBlank = MySQL.convertString(socket)

		defer {
			self.cleanConvertedString(hostOrBlank)
			self.cleanConvertedString(userOrBlank)
			self.cleanConvertedString(passwordOrBlank)
			self.cleanConvertedString(dbOrBlank)
			self.cleanConvertedString(socketOrBlank)
		}
		
		let check = mysql_real_connect(self.ptr, hostOrBlank.0, userOrBlank.0, passwordOrBlank.0, dbOrBlank.0, port, socketOrBlank.0, flag)
		return check != nil && check == self.ptr
	}
	
	public func selectDatabase(named: String) -> Bool {
		let r = mysql_select_db(self.ptr, named)
		return r == 0
	}
	
	public func listTables(wild: String? = nil) -> [String] {
		var result = [String]()
		let res = (wild == nil ? mysql_list_tables(self.ptr, nil) : mysql_list_tables(self.ptr, wild!))
		if res != nil {
			var row = mysql_fetch_row(res)
			while row != nil {
				result.append(String(validatingUTF8: row[0]) ?? "")
				row = mysql_fetch_row(res)
			}
			mysql_free_result(res)
		}
		return result
	}
	
	public func listDatabases(wild: String? = nil) -> [String] {
		var result = [String]()
		let res = wild == nil ? mysql_list_dbs(self.ptr, nil) : mysql_list_dbs(self.ptr, wild!)
		if res != nil {
			var row = mysql_fetch_row(res)
			while row != nil {
				result.append(String(validatingUTF8: row[0]) ?? "")
				row = mysql_fetch_row(res)
			}
			mysql_free_result(res)
		}
		return result
	}
	
	public func commit() -> Bool {
		let r = mysql_commit(self.ptr)
		return r == 1
	}
	
	public func rollback() -> Bool {
		let r = mysql_rollback(self.ptr)
		return r == 1
	}
	
	public func moreResults() -> Bool {
		let r = mysql_more_results(self.ptr)
		return r == 1
	}
	
	public func nextResult() -> Int {
		let r = mysql_next_result(self.ptr)
		return Int(r)
	}
	
	public func query(stmt: String) -> Bool {
		let r = mysql_real_query(self.ptr, stmt, UInt(stmt.utf8.count))
		return r == 0
	}
	
    public func storeResults() -> MySQL.Results? {
        let ret = mysql_store_result(self.ptr)
        if ret == nil {
            return nil
        }
		return MySQL.Results(ret)
	}
	
	func exposedOptionToMySQLOption(o: MySQLOpt) -> mysql_option {
		switch o {
		case MySQLOpt.MYSQL_OPT_CONNECT_TIMEOUT:
			return MYSQL_OPT_CONNECT_TIMEOUT
		case MySQLOpt.MYSQL_OPT_COMPRESS:
			return MYSQL_OPT_COMPRESS
		case MySQLOpt.MYSQL_OPT_NAMED_PIPE:
			return MYSQL_OPT_NAMED_PIPE
		case MySQLOpt.MYSQL_INIT_COMMAND:
			return MYSQL_INIT_COMMAND
		case MySQLOpt.MYSQL_READ_DEFAULT_FILE:
			return MYSQL_READ_DEFAULT_FILE
		case MySQLOpt.MYSQL_READ_DEFAULT_GROUP:
			return MYSQL_READ_DEFAULT_GROUP
		case MySQLOpt.MYSQL_SET_CHARSET_DIR:
			return MYSQL_SET_CHARSET_DIR
		case MySQLOpt.MYSQL_SET_CHARSET_NAME:
			return MYSQL_SET_CHARSET_NAME
		case MySQLOpt.MYSQL_OPT_LOCAL_INFILE:
			return MYSQL_OPT_LOCAL_INFILE
		case MySQLOpt.MYSQL_OPT_PROTOCOL:
			return MYSQL_OPT_PROTOCOL
		case MySQLOpt.MYSQL_SHARED_MEMORY_BASE_NAME:
			return MYSQL_SHARED_MEMORY_BASE_NAME
		case MySQLOpt.MYSQL_OPT_READ_TIMEOUT:
			return MYSQL_OPT_READ_TIMEOUT
		case MySQLOpt.MYSQL_OPT_WRITE_TIMEOUT:
			return MYSQL_OPT_WRITE_TIMEOUT
		case MySQLOpt.MYSQL_OPT_USE_RESULT:
			return MYSQL_OPT_USE_RESULT
		case MySQLOpt.MYSQL_OPT_USE_REMOTE_CONNECTION:
			return MYSQL_OPT_USE_REMOTE_CONNECTION
		case MySQLOpt.MYSQL_OPT_USE_EMBEDDED_CONNECTION:
			return MYSQL_OPT_USE_EMBEDDED_CONNECTION
		case MySQLOpt.MYSQL_OPT_GUESS_CONNECTION:
			return MYSQL_OPT_GUESS_CONNECTION
		case MySQLOpt.MYSQL_SET_CLIENT_IP:
			return MYSQL_SET_CLIENT_IP
		case MySQLOpt.MYSQL_SECURE_AUTH:
			return MYSQL_SECURE_AUTH
		case MySQLOpt.MYSQL_REPORT_DATA_TRUNCATION:
			return MYSQL_REPORT_DATA_TRUNCATION
		case MySQLOpt.MYSQL_OPT_RECONNECT:
			return MYSQL_OPT_RECONNECT
		case MySQLOpt.MYSQL_OPT_SSL_VERIFY_SERVER_CERT:
			return MYSQL_OPT_SSL_VERIFY_SERVER_CERT
		case MySQLOpt.MYSQL_PLUGIN_DIR:
			return MYSQL_PLUGIN_DIR
		case MySQLOpt.MYSQL_DEFAULT_AUTH:
			return MYSQL_DEFAULT_AUTH
		case MySQLOpt.MYSQL_OPT_BIND:
			return MYSQL_OPT_BIND
		case MySQLOpt.MYSQL_OPT_SSL_KEY:
			return MYSQL_OPT_SSL_KEY
		case MySQLOpt.MYSQL_OPT_SSL_CERT:
			return MYSQL_OPT_SSL_CERT
		case MySQLOpt.MYSQL_OPT_SSL_CA:
			return MYSQL_OPT_SSL_CA
		case MySQLOpt.MYSQL_OPT_SSL_CAPATH:
			return MYSQL_OPT_SSL_CAPATH
		case MySQLOpt.MYSQL_OPT_SSL_CIPHER:
			return MYSQL_OPT_SSL_CIPHER
		case MySQLOpt.MYSQL_OPT_SSL_CRL:
			return MYSQL_OPT_SSL_CRL
		case MySQLOpt.MYSQL_OPT_SSL_CRLPATH:
			return MYSQL_OPT_SSL_CRLPATH
		case MySQLOpt.MYSQL_OPT_CONNECT_ATTR_RESET:
			return MYSQL_OPT_CONNECT_ATTR_RESET
		case MySQLOpt.MYSQL_OPT_CONNECT_ATTR_ADD:
			return MYSQL_OPT_CONNECT_ATTR_ADD
		case MySQLOpt.MYSQL_OPT_CONNECT_ATTR_DELETE:
			return MYSQL_OPT_CONNECT_ATTR_DELETE
		case MySQLOpt.MYSQL_SERVER_PUBLIC_KEY:
			return MYSQL_SERVER_PUBLIC_KEY
		case MySQLOpt.MYSQL_ENABLE_CLEARTEXT_PLUGIN:
			return MYSQL_ENABLE_CLEARTEXT_PLUGIN
		case MySQLOpt.MYSQL_OPT_CAN_HANDLE_EXPIRED_PASSWORDS:
			return MYSQL_OPT_CAN_HANDLE_EXPIRED_PASSWORDS
		}
	}
	
	public func setOption(option: MySQLOpt) -> Bool {
		return mysql_options(self.ptr, exposedOptionToMySQLOption(option), nil) == 0
	}
	
	public func setOption(option: MySQLOpt, _ b: Bool) -> Bool {
		var myB = my_bool(b ? 1 : 0)
		return mysql_options(self.ptr, exposedOptionToMySQLOption(option), &myB) == 0
	}
	
	public func setOption(option: MySQLOpt, _ i: Int) -> Bool {
		var myI = UInt32(i)
		return mysql_options(self.ptr, exposedOptionToMySQLOption(option), &myI) == 0
	}
	
	public func setOption(option: MySQLOpt, _ s: String) -> Bool {
		var b = false
		s.withCString { p in
			b = mysql_options(self.ptr, exposedOptionToMySQLOption(option), p) == 0
		}
		return b
	}
	
	public final class Results: IteratorProtocol {
		var ptr: UnsafeMutablePointer<MYSQL_RES>
		
		public typealias Element = [String]
		
		init(_ ptr: UnsafeMutablePointer<MYSQL_RES>) {
			self.ptr = ptr
		}
		
		deinit {
			self.close()
		}
		
		public func close() {
			if self.ptr != nil {
				mysql_free_result(self.ptr)
				self.ptr = nil
			}
		}
		
		public func dataSeek(offset: UInt) {
			mysql_data_seek(self.ptr, my_ulonglong(offset))
		}
		
		public func numRows() -> Int {
			return Int(mysql_num_rows(self.ptr))
		}
		
		public func numFields() -> Int {
			return Int(mysql_num_fields(self.ptr))
		}
		
		public func next() -> Element? {
			let row = mysql_fetch_row(self.ptr)
			guard row != nil else {
				return nil
			}
			
			let lengths = mysql_fetch_lengths(self.ptr)
			var ret = [String]()
			
			for fieldIdx in 0..<self.numFields() {
				let len = Int(lengths[fieldIdx])
				let raw = UnsafeMutablePointer<UInt8>(row[fieldIdx])
				let s = UTF8Encoding.encode(GenerateFromPointer(from: raw, count: len))
				ret.append(s)
			}
			return ret
		}
		
		public func forEachRow(callback: (Element) -> ()) {
			while true {
				let row = mysql_fetch_row(self.ptr)
				guard row != nil else {
					return
				}
				
				let lengths = mysql_fetch_lengths(self.ptr)
				var ret = [String]()
				
				for fieldIdx in 0..<self.numFields() {
					let len = Int(lengths[fieldIdx])
					let raw = UnsafeMutablePointer<UInt8>(row[fieldIdx])
					let s = UTF8Encoding.encode(GenerateFromPointer(from: raw, count: len))
					ret.append(s)
				}
				callback(ret)
			}
		}
	}
}

public final class MySQLStmt {
	private var ptr: UnsafeMutablePointer<MYSQL_STMT>
	private var paramBinds = UnsafeMutablePointer<MYSQL_BIND>(nil)
	private var paramBindsOffset = 0
	
	public enum FetchResult {
		case OK, Error, NoData, DataTruncated
	}
	
	public init(_ mysql: MySQL) {
		self.ptr = mysql_stmt_init(mysql.ptr)
	}
	
	deinit {
		self.close()
	}
	
	public func close() {
		clearBinds()
		if self.ptr != nil {
			mysql_stmt_close(self.ptr)
			self.ptr = nil
		}
	}
	
	public func reset() {
		clearBinds()
		mysql_stmt_reset(self.ptr)
	}
	
	func clearBinds() {
		let count = self.paramBindsOffset
		if count > 0 {
			for i in 0..<count {
				switch self.paramBinds[i].buffer_type.rawValue {
				case MYSQL_TYPE_DOUBLE.rawValue:
					UnsafeMutablePointer<Double>(self.paramBinds[i].buffer).deallocateCapacity(1)
				case MYSQL_TYPE_LONGLONG.rawValue:
                    if self.paramBinds[i].is_unsigned == 1 {
                        UnsafeMutablePointer<UInt64>(self.paramBinds[i].buffer).deallocateCapacity(1)
                    } else {
                        UnsafeMutablePointer<Int64>(self.paramBinds[i].buffer).deallocateCapacity(1)
                    }
				case MYSQL_TYPE_VAR_STRING.rawValue,
					MYSQL_TYPE_DATE.rawValue,
					MYSQL_TYPE_DATETIME.rawValue:
					UnsafeMutablePointer<Int8>(self.paramBinds[i].buffer).deallocateCapacity(Int(self.paramBinds[i].buffer_length))
				case MYSQL_TYPE_LONG_BLOB.rawValue:
					()
				default:
					assertionFailure("Unhandled MySQL type \(self.paramBinds[i].buffer_type)")
				}
				if self.paramBinds[i].length != nil {
					self.paramBinds[i].length.deallocateCapacity(1)
				}
			}
			self.paramBinds.deinitialize(count: count)
			self.paramBinds.deallocateCapacity(count)
			self.paramBindsOffset = 0
		}
	}
	
	public func freeResult() {
		mysql_stmt_free_result(self.ptr)
	}
	
	public func errorCode() -> UInt32 {
		return mysql_stmt_errno(self.ptr)
	}
	
	public func errorMessage() -> String {
		return String(validatingUTF8: mysql_stmt_error(self.ptr)) ?? ""
	}
	
	public func prepare(query: String) -> Bool {
		let utf8Chars = query.utf8
		let r = mysql_stmt_prepare(self.ptr, query, UInt(utf8Chars.count))
		guard r == 0 else {
			return false
		}
		let count = self.paramCount()
		if count > 0 {
			self.paramBinds = UnsafeMutablePointer<MYSQL_BIND>.alloc(count)
			let initBind = MYSQL_BIND()
			for i in 0..<count {
				self.paramBinds.advanced(by: i).initialize(with: initBind)
			}
			
		}
		return true
	}
	
	public func execute() -> Bool {
		if self.paramBindsOffset > 0 {
			guard 0 == mysql_stmt_bind_param(self.ptr, self.paramBinds) else {
				return false
			}
		}
		let r = mysql_stmt_execute(self.ptr)
		return r == 0
	}
	
	public func results() -> MySQLStmt.Results {
		return Results(self)
	}
	
	public func fetch() -> FetchResult {
		let r = mysql_stmt_fetch(self.ptr)
		switch r {
		case 0:
			return .OK
		case 1:
			return .Error
		case MYSQL_NO_DATA:
			return .NoData
		case MYSQL_DATA_TRUNCATED:
			return .DataTruncated
		default:
			return .Error
		}
	}
	
	public func numRows() -> UInt {
		return UInt(mysql_stmt_num_rows(self.ptr))
	}
	
	public func affectedRows() -> UInt {
		return UInt(mysql_stmt_affected_rows(self.ptr))
	}
	
	public func insertId() -> UInt {
		return UInt(mysql_stmt_insert_id(self.ptr))
	}
	
	public func fieldCount() -> UInt {
		return UInt(mysql_stmt_field_count(self.ptr))
	}
	
	public func nextResult() -> Int {
		let r = mysql_stmt_next_result(self.ptr)
		return Int(r)
	}
	
	public func dataSeek(offset: Int) {
		mysql_stmt_data_seek(self.ptr, my_ulonglong(offset))
	}
	
	public func paramCount() -> Int {
		let r = mysql_stmt_param_count(self.ptr)
		return Int(r)
	}
	
	func bindParam(s: String, type: enum_field_types) -> Bool {
		let convertedTup = MySQL.convertString(s)
		self.paramBinds[self.paramBindsOffset].buffer_type = type
		self.paramBinds[self.paramBindsOffset].buffer_length = UInt(convertedTup.1-1)
		self.paramBinds[self.paramBindsOffset].length = UnsafeMutablePointer<UInt>.alloc(1)
		self.paramBinds[self.paramBindsOffset].length.initialize(with: UInt(convertedTup.1-1))
		self.paramBinds[self.paramBindsOffset].buffer = UnsafeMutablePointer<()>(convertedTup.0)
		
		self.paramBindsOffset += 1
		return true
	}
	
	public func bindParam(d: Double) -> Bool {
		self.paramBinds[self.paramBindsOffset].buffer_type = MYSQL_TYPE_DOUBLE
		self.paramBinds[self.paramBindsOffset].buffer_length = UInt(sizeof(Double))
		let a = UnsafeMutablePointer<Double>.alloc(1)
		a.initialize(with: d)
		self.paramBinds[self.paramBindsOffset].buffer = UnsafeMutablePointer<()>(a)
		
		self.paramBindsOffset += 1
		return true
    }
    
    public func bindParam(i: Int) -> Bool {
        self.paramBinds[self.paramBindsOffset].buffer_type = MYSQL_TYPE_LONGLONG
        self.paramBinds[self.paramBindsOffset].buffer_length = UInt(sizeof(Int64))
        let a = UnsafeMutablePointer<Int64>.alloc(1)
        a.initialize(with: Int64(i))
        self.paramBinds[self.paramBindsOffset].buffer = UnsafeMutablePointer<()>(a)
        
        self.paramBindsOffset += 1
        return true
    }
    
    public func bindParam(i: UInt64) -> Bool {
        self.paramBinds[self.paramBindsOffset].buffer_type = MYSQL_TYPE_LONGLONG
        self.paramBinds[self.paramBindsOffset].buffer_length = UInt(sizeof(UInt64))
        let a = UnsafeMutablePointer<UInt64>.alloc(1)
        a.initialize(with: UInt64(i))
        self.paramBinds[self.paramBindsOffset].is_unsigned = 1
        self.paramBinds[self.paramBindsOffset].buffer = UnsafeMutablePointer<()>(a)
        
        self.paramBindsOffset += 1
        return true
    }
	
	public func bindParam(s: String) -> Bool {
		let convertedTup = MySQL.convertString(s)
		self.paramBinds[self.paramBindsOffset].buffer_type = MYSQL_TYPE_VAR_STRING
		self.paramBinds[self.paramBindsOffset].buffer_length = UInt(convertedTup.1-1)
		self.paramBinds[self.paramBindsOffset].length = UnsafeMutablePointer<UInt>.alloc(1)
		self.paramBinds[self.paramBindsOffset].length.initialize(with: UInt(convertedTup.1-1))
		self.paramBinds[self.paramBindsOffset].buffer = UnsafeMutablePointer<()>(convertedTup.0)
		
		self.paramBindsOffset += 1
		return true
	}
	
	public func bindParam(b: UnsafePointer<Int8>, length: Int) -> Bool {
		self.paramBinds[self.paramBindsOffset].buffer_type = MYSQL_TYPE_LONG_BLOB
		self.paramBinds[self.paramBindsOffset].buffer_length = UInt(length)
		self.paramBinds[self.paramBindsOffset].length = UnsafeMutablePointer<UInt>.alloc(1)
		self.paramBinds[self.paramBindsOffset].length.initialize(with: UInt(length))
		self.paramBinds[self.paramBindsOffset].buffer = UnsafeMutablePointer<()>(b)
		
		self.paramBindsOffset += 1
		return true
	}
	
	public func bindParam(b: [UInt8]) -> Bool {
		self.paramBinds[self.paramBindsOffset].buffer_type = MYSQL_TYPE_LONG_BLOB
		self.paramBinds[self.paramBindsOffset].buffer_length = UInt(b.count)
		self.paramBinds[self.paramBindsOffset].length = UnsafeMutablePointer<UInt>.alloc(1)
		self.paramBinds[self.paramBindsOffset].length.initialize(with: UInt(b.count))
		self.paramBinds[self.paramBindsOffset].buffer = UnsafeMutablePointer<()>(b)
		
		self.paramBindsOffset += 1
		return true
	}
	
	// null
	public func bindParam() -> Bool {
		self.paramBinds[self.paramBindsOffset].buffer_type = MYSQL_TYPE_NULL
		self.paramBinds[self.paramBindsOffset].length = UnsafeMutablePointer<UInt>.alloc(1)
		self.paramBindsOffset += 1
		return true
	}
	
	public final class Results: IteratorProtocol {
        let _UNSIGNED_FLAG = UInt32(UNSIGNED_FLAG)
		public typealias Element = [Any?]
		
		let stmt: MySQLStmt
		public let numFields: Int
		
		var meta: UnsafeMutablePointer<MYSQL_RES>
		let binds: UnsafeMutablePointer<MYSQL_BIND>
		
		let lengthBuffers: UnsafeMutablePointer<UInt>
		let isNullBuffers: UnsafeMutablePointer<my_bool>
		
		init(_ stmt: MySQLStmt) {
			self.stmt = stmt
			numFields = Int(stmt.fieldCount())
			
			binds = UnsafeMutablePointer<MYSQL_BIND>.alloc(numFields)
			
			lengthBuffers = UnsafeMutablePointer<UInt>.alloc(numFields)
			isNullBuffers = UnsafeMutablePointer<my_bool>.alloc(numFields)
			
			meta = mysql_stmt_result_metadata(self.stmt.ptr)
		}
		
		deinit {
			self.close()
		}
		
		public func close() {
			if meta != nil {
				mysql_free_result(meta)
				
				binds.deallocateCapacity(numFields)
				
				lengthBuffers.deallocateCapacity(numFields)
				isNullBuffers.deallocateCapacity(numFields)
				
				meta = nil
			}
		}
		
		public var numRows: Int {
			return Int(self.stmt.numRows())
		}
		
		public func next() -> Element? {
			
			return nil
		}
		
		enum GeneralType {
			case Integer(enum_field_types),
				Double(enum_field_types),
				Bytes(enum_field_types),
				String(enum_field_types),
				Date(enum_field_types),
				Null
		}
		
		func mysqlTypeToGeneralType(type: enum_field_types) -> GeneralType {
			switch type {
			case MYSQL_TYPE_NULL:
				return .Null
			case MYSQL_TYPE_FLOAT,
				MYSQL_TYPE_DOUBLE:
				return .Double(type)
			case MYSQL_TYPE_TINY,
				MYSQL_TYPE_SHORT,
				MYSQL_TYPE_LONG,
				MYSQL_TYPE_INT24,
				MYSQL_TYPE_LONGLONG:
				return .Integer(type)
			case MYSQL_TYPE_TIMESTAMP,
				MYSQL_TYPE_DATE,
				MYSQL_TYPE_TIME,
				MYSQL_TYPE_DATETIME,
				MYSQL_TYPE_YEAR,
				MYSQL_TYPE_NEWDATE:
				return .Date(type)
			case MYSQL_TYPE_TINY_BLOB,
				MYSQL_TYPE_MEDIUM_BLOB,
				MYSQL_TYPE_LONG_BLOB,
				MYSQL_TYPE_BLOB:
				return .Bytes(type)
			case MYSQL_TYPE_DECIMAL,
				MYSQL_TYPE_NEWDECIMAL:
				return .String(type)
			default:
				return .String(type)
			}
		}
		
		func bindField(field: UnsafeMutablePointer<MYSQL_FIELD>) -> MYSQL_BIND {
			let fieldType = field.pointee.type
			let generalType = mysqlTypeToGeneralType(fieldType)
			let bind = bindToType(generalType)
			return bind
		}
		
		func bindBuffer<T>(sourceBind: MYSQL_BIND, type: T) -> MYSQL_BIND {
			var bind = sourceBind
			bind.buffer = UnsafeMutablePointer<()>(UnsafeMutablePointer<T>.alloc(1))
			bind.buffer_length = UInt(sizeof(T))
			return bind
		}
        
		public func forEachRow(callback: Element -> ()) -> Bool {
			
			let scratch = UnsafeMutablePointer<()>(UnsafeMutablePointer<Int8>.alloc(0))
			
			for i in 0..<numFields {
				let field = mysql_fetch_field_direct(meta, UInt32(i))
                let f: MYSQL_FIELD = field.pointee
				var bind = bindField(field)
				bind.length = lengthBuffers.advanced(by: i)
				bind.length.initialize(with: 0)
				bind.is_null = isNullBuffers.advanced(by: i)
				bind.is_null.initialize(with: 0)
				
				let genType = mysqlTypeToGeneralType(bind.buffer_type)
				switch genType {
				case .Double:
                    switch bind.buffer_type {
                    case MYSQL_TYPE_FLOAT:
                        bind = bindBuffer(bind, type: Float.self);
                    case MYSQL_TYPE_DOUBLE:
                        bind = bindBuffer(bind, type: Double.self);
                    default: break
                    }
                case .Integer:
                    if (f.flags & _UNSIGNED_FLAG) == _UNSIGNED_FLAG {
                        bind.is_unsigned = 1
                        switch bind.buffer_type {
                        case MYSQL_TYPE_LONGLONG:
                            bind = bindBuffer(bind, type: CUnsignedLongLong.self);
                        case MYSQL_TYPE_LONG, MYSQL_TYPE_INT24:
                            bind = bindBuffer(bind, type: CUnsignedInt.self);
                        case MYSQL_TYPE_SHORT:
                            bind = bindBuffer(bind, type: CUnsignedShort.self);
                        case MYSQL_TYPE_TINY:
                            bind = bindBuffer(bind, type: CUnsignedChar.self);
                        default: break
                        }
                    } else {
                        switch bind.buffer_type {
                        case MYSQL_TYPE_LONGLONG:
                            bind = bindBuffer(bind, type: CLongLong.self);
                        case MYSQL_TYPE_LONG, MYSQL_TYPE_INT24:
                            bind = bindBuffer(bind, type: CInt.self);
                        case MYSQL_TYPE_SHORT:
                            bind = bindBuffer(bind, type: CShort.self);
                        case MYSQL_TYPE_TINY:
                            bind = bindBuffer(bind, type: CChar.self);
                        default: break
                        }
                    }
				case .Bytes, .String, .Date, .Null:
					bind.buffer = scratch
					bind.buffer_length = 0
				}
				
				binds.advanced(by: i).initialize(with: bind)
			}
			
			defer {
				for i in 0..<numFields {
					let bind = binds[i]
					let genType = mysqlTypeToGeneralType(bind.buffer_type)
					switch genType {
					case .Double:
                        switch bind.buffer_type {
                        case MYSQL_TYPE_FLOAT:
                            UnsafeMutablePointer<Float>(bind.buffer).deallocateCapacity(1)
                        case MYSQL_TYPE_DOUBLE:
                            UnsafeMutablePointer<Double>(bind.buffer).deallocateCapacity(1)
                        default: break
                        }
					case .Integer:
                        if bind.is_unsigned == 1 {
                            switch bind.buffer_type {
                            case MYSQL_TYPE_LONGLONG:
                                UnsafeMutablePointer<CUnsignedLongLong>(bind.buffer).deallocateCapacity(1)
                            case MYSQL_TYPE_LONG, MYSQL_TYPE_INT24:
                                UnsafeMutablePointer<CUnsignedInt>(bind.buffer).deallocateCapacity(1)
                            case MYSQL_TYPE_SHORT:
                                UnsafeMutablePointer<CUnsignedShort>(bind.buffer).deallocateCapacity(1)
                            case MYSQL_TYPE_TINY:
                                UnsafeMutablePointer<CUnsignedChar>(bind.buffer).deallocateCapacity(1)
                            default: break
                            }
                        } else {
                            switch bind.buffer_type {
                            case MYSQL_TYPE_LONGLONG:
                                UnsafeMutablePointer<CLongLong>(bind.buffer).deallocateCapacity(1)
                            case MYSQL_TYPE_LONG, MYSQL_TYPE_INT24:
                                UnsafeMutablePointer<CInt>(bind.buffer).deallocateCapacity(1)
                            case MYSQL_TYPE_SHORT:
                                UnsafeMutablePointer<CShort>(bind.buffer).deallocateCapacity(1)
                            case MYSQL_TYPE_TINY:
                                UnsafeMutablePointer<CChar>(bind.buffer).deallocateCapacity(1)
                            default: break
                            }
                        }
					case .Bytes, .String, .Date, .Null:
						() // do nothing. these were cleaned right after use or not allocated at all
					}
				}
			}
			
			guard 0 == mysql_stmt_bind_result(self.stmt.ptr, binds) else {
				return false
			}
			
			while true {
				
				let fetchRes = mysql_stmt_fetch(self.stmt.ptr)
				if fetchRes == MYSQL_NO_DATA {
					return true
				}
				if fetchRes == 1 {
					return false
				}
				
				var row = Element()
				
				for i in 0..<numFields {
					var bind = binds[i]
					let genType = mysqlTypeToGeneralType(bind.buffer_type)
					let length = Int(bind.length.pointee)
					let isNull = bind.is_null.pointee
					
					if isNull != 0 {
						row.append(nil)
					} else {
						
						switch genType {
						case .Double:
                            switch bind.buffer_type {
                            case MYSQL_TYPE_FLOAT:
                                let f = UnsafeMutablePointer<Float>(bind.buffer).pointee
                                row.append(f)
                            case MYSQL_TYPE_DOUBLE:
                                let f = UnsafeMutablePointer<Double>(bind.buffer).pointee
                                row.append(f)
                            default: break
                            }
						case .Integer:
                            if bind.is_unsigned == 1 {
                                switch bind.buffer_type {
                                case MYSQL_TYPE_LONGLONG:
                                    let i = UnsafeMutablePointer<CUnsignedLongLong>(bind.buffer).pointee
                                    row.append(i)
                                case MYSQL_TYPE_LONG, MYSQL_TYPE_INT24:
                                    let i = UnsafeMutablePointer<CUnsignedInt>(bind.buffer).pointee
                                    row.append(i)
                                case MYSQL_TYPE_SHORT:
                                    let i = UnsafeMutablePointer<CUnsignedShort>(bind.buffer).pointee
                                    row.append(i)
                                case MYSQL_TYPE_TINY:
                                    let i = UnsafeMutablePointer<CUnsignedChar>(bind.buffer).pointee
                                    row.append(i)
                                default: break
                                }
                            } else {
                                switch bind.buffer_type {
                                case MYSQL_TYPE_LONGLONG:
                                    let i = UnsafeMutablePointer<CLongLong>(bind.buffer).pointee
                                    row.append(i)
                                case MYSQL_TYPE_LONG, MYSQL_TYPE_INT24:
                                    let i = UnsafeMutablePointer<CInt>(bind.buffer).pointee
                                    row.append(i)
                                case MYSQL_TYPE_SHORT:
                                    let i = UnsafeMutablePointer<CShort>(bind.buffer).pointee
                                    row.append(i)
                                case MYSQL_TYPE_TINY:
                                    let i = UnsafeMutablePointer<CChar>(bind.buffer).pointee
                                    row.append(i)
                                default: break
                                }
                            }
						case .Bytes:
							
							let raw = UnsafeMutablePointer<UInt8>.alloc(length)
							defer {
								raw.deallocateCapacity(length)
							}
							bind.buffer = UnsafeMutablePointer<()>(raw)
							bind.buffer_length = UInt(length)
							
							let res = mysql_stmt_fetch_column(self.stmt.ptr, &bind, UInt32(i), 0)
							guard res == 0 else {
								return false
							}
							
							var a = [UInt8]()
							var gen = GenerateFromPointer(from: raw, count: length)
							while let c = gen.next() {
								a.append(c)
							}
							row.append(a)
							
						case .String, .Date:
							
							let raw = UnsafeMutablePointer<UInt8>.alloc(length)
							defer {
								raw.deallocateCapacity(length)
							}
							bind.buffer = UnsafeMutablePointer<()>(raw)
							bind.buffer_length = UInt(length)
							
							let res = mysql_stmt_fetch_column(self.stmt.ptr, &bind, UInt32(i), 0)
							guard res == 0 else {
								return false
							}
							
							let s = UTF8Encoding.encode(GenerateFromPointer(from: raw, count: length))
							row.append(s)
							
						case .Null:
							row.append(nil)
						}
					}
				}
				
				callback(row)
			}
			// @unreachable
		}
		
		func bindToType(type: GeneralType) -> MYSQL_BIND {
			switch type {
			case .Double(let s):
				return bindToIntegral(s)
			case .Integer(let s):
				return bindToIntegral(s)
			case .Bytes:
				return bindToBlob()
			case .String, .Date:
				return bindToString()
			case .Null:
				return bindToNull()
			}
		}
		
		func bindToBlob() -> MYSQL_BIND {
			var bind = MYSQL_BIND()
			bind.buffer_type = MYSQL_TYPE_LONG_BLOB
			return bind
		}
		
		func bindToString() -> MYSQL_BIND {
			var bind = MYSQL_BIND()
			bind.buffer_type = MYSQL_TYPE_VAR_STRING
			return bind
		}
		
		func bindToNull() -> MYSQL_BIND {
			var bind = MYSQL_BIND()
			bind.buffer_type = MYSQL_TYPE_NULL
			return bind
		}
		
		func bindToIntegral(type: enum_field_types) -> MYSQL_BIND {
			var bind = MYSQL_BIND()
			bind.buffer_type = type
			return bind
		}
	}
}
