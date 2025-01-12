module callisto.parser;

import std.conv;
import std.range;
import std.stdio;
import std.format;
import std.algorithm;
import callisto.error;
import callisto.lexer;

enum NodeType {
	Null,
	Word,
	Integer,
	FuncDef,
	Include,
	Asm,
	If,
	While,
	Let,
	Enable,
	Requires,
	Version,
	Array,
	String,
	Struct,
	Const,
	Enum,
	Restrict,
	Union,
	Alias,
	Extern,
	Addr,
	Implement,
	Set
}

class Node {
	NodeType  type;
	ErrorInfo error;

	this() {

	}
}

class WordNode : Node {
	string name;

	this(ErrorInfo perror) {
		type  = NodeType.Word;
		error = perror;
	}

	this(ErrorInfo perror, string pname) {
		type  = NodeType.Word;
		error = perror;
		name  = pname;
	}

	override string toString() => name;
}

class IntegerNode : Node {
	long value;

	this(ErrorInfo perror) {
		type  = NodeType.Integer;
		error = perror;
	}

	this(ErrorInfo perror, long pvalue) {
		error = perror;
		type  = NodeType.Integer;
		value = pvalue;
	}

	override string toString() => format("%d", value);
}

class FuncDefNode : Node {
	string   name;
	Node[]   nodes;
	bool     inline;
	bool     raw;
	string[] paramTypes;
	string[] params;

	this(ErrorInfo perror) {
		type  = NodeType.FuncDef;
		error = perror;
	}

	override string toString() {
		string ret = format("func %s", name);

		foreach (i, ref param ; params) {
			ret ~= format(" %s %s", paramTypes[i], param);
		}
		ret ~= " begin\n";

		foreach (ref node ; nodes) {
			ret ~= "    " ~ node.toString() ~ '\n';
		}

		return ret ~ "\nend";
	}
}

class IncludeNode : Node {
	string path;

	this(ErrorInfo perror) {
		type  = NodeType.Include;
		error = perror;
	}

	override string toString() => format("include \"%s\"", path);
}

class AsmNode : Node {
	string code;

	this(ErrorInfo perror) {
		type  = NodeType.Asm;
		error = perror;
	}

	this(ErrorInfo perror, string pcode) {
		type  = NodeType.Asm;
		error = perror;
		code  = pcode;
	}

	override string toString() => format("asm %s", code);
}

class IfNode : Node {
	Node[][] condition;
	Node[][] doIf;
	bool     hasElse;
	Node[]   doElse;

	this(ErrorInfo perror) {
		type  = NodeType.If;
		error = perror;
	}

	override string toString() {
		string ret;

		auto condition2 = condition;
		auto doIf2      = doIf;

		foreach (i, ref icondition ; condition) {
			ret ~= i == 0? "if " : "elseif ";

			foreach (ref node ; icondition) {
				ret ~= node.toString ~ ' ';
			}
			ret ~= "then\n";
			
			foreach (ref node ; doIf[i]) {
				ret ~= node.toString() ~ '\n';
			}
		}

		if (hasElse) {
			ret ~= "else\n";

			foreach (ref node ; doElse) {
				ret ~= node.toString() ~ '\n';
			}
		}

		return ret ~ "end";
	}
}

class WhileNode : Node {
	Node[] condition;
	Node[] doWhile;

	this(ErrorInfo perror) {
		error = perror;
		type  = NodeType.While;
	}

	override string toString() {
		string ret = "while ";

		foreach (ref node ; condition) {
			ret ~= node.toString() ~ ' ';
		}

		ret ~= "do\n";

		foreach (ref node ; doWhile) {
			ret ~= node.toString() ~ '\n';
		}

		return ret ~ "end";
	}
}

class LetNode : Node {
	string varType;
	string name;
	bool   array;
	size_t arraySize;

	this(ErrorInfo perror) {
		type  = NodeType.Let;
		error = perror;
	}

	override string toString() => array?
		format("let array %d %s %s", arraySize, varType, name) :
		format("let %s %s", varType, name);
}

class EnableNode : Node {
	string ver;

	this(ErrorInfo perror) {
		type  = NodeType.Enable;
		error = perror;
	}

	override string toString() => format("enable %s", ver);
}

class RequiresNode : Node {
	string ver;

	this(ErrorInfo perror) {
		type  = NodeType.Requires;
		error = perror;
	}

	override string toString() => format("requires %s", ver);
}

class VersionNode : Node {
	string ver;
	bool   not;
	Node[] block;

	this(ErrorInfo perror) {
		type  = NodeType.Version;
		error = perror;
	}

	override string toString() {
		string ret = format("version %s\n", ver);

		foreach (ref node ; block) {
			ret ~= format("    %s\n", node);
		}

		return ret ~ "end";
	}
}

class ArrayNode : Node {
	string arrayType;
	Node[] elements;
	bool   constant;

	this(ErrorInfo perror) {
		type  = NodeType.Array;
		error = perror;
	}

	override string toString() {
		string ret = constant? "c[" : "[";

		foreach (ref node ; elements) {
			ret ~= node.toString() ~ ' ';
		}

		return ret ~ ']';
	}
}

class StringNode : Node {
	string value;
	bool   constant;

	this(ErrorInfo perror) {
		type  = NodeType.String;
		error = perror;
	}

	override string toString() => format("%s\"%s\"", constant? "c" : "", value);
}

struct StructMember {
	string type;
	string name;
	bool   array;
	size_t size;

	string toString() {
		return array?
			format("array %d %s %s", size, type, name) :
			format("%s %s", type, name);
	}
}

class StructNode : Node {
	string         name;
	StructMember[] members;
	bool           inherits;
	string         inheritsFrom;

	this(ErrorInfo perror) {
		type  = NodeType.Struct;
		error = perror;
	}

	override string toString() {
		string ret = inherits?
			format("struct %s : %s\n", name, inheritsFrom) :
			format("struct %s\n", name);

		foreach (ref member ; members) {
			ret ~= "    " ~ member.toString() ~ '\n';
		}

		return ret ~ "end";
	}
}

class ConstNode : Node {
	string name;
	long   value;

	this(ErrorInfo perror) {
		type  = NodeType.Const;
		error = perror;
	}

	override string toString() => format("const %s %d", name, value);
}

class EnumNode : Node {
	string   name;
	string   enumType;
	string[] names;
	long[]   values;

	this(ErrorInfo perror) {
		type  = NodeType.Enum;
		error = perror;
	}

	override string toString() {
		string ret = format("enum %s : %s\n", name, enumType);

		foreach (i, ref name ; names) {
			ret ~= format("    %s = %d\n", name, values[i]);
		}

		return ret ~ "end\n";
	}
}

class RestrictNode : Node {
	string ver;

	this(ErrorInfo perror) {
		type  = NodeType.Restrict;
		error = perror;
	}

	override string toString() => format("restrict %s", ver);
}

class UnionNode : Node {
	string   name;
	string[] types;

	this(ErrorInfo perror) {
		type  = NodeType.Union;
		error = perror;
	}

	override string toString() {
		auto ret = format("union %s\n", name);

		foreach (ref type ; types) {
			ret ~= format("    %s\n", type);
		}

		return ret ~ "end";
	}
}

class AliasNode : Node {
	string to;
	string from;
	bool   overwrite;

	this(ErrorInfo perror) {
		type  = NodeType.Alias;
		error = perror;
	}

	override string toString() => format("alias %s %s", to, from);
}

enum ExternType {
	Callisto,
	Raw,
	C
}

class ExternNode : Node {
	string     func;
	ExternType externType;

	// for C extern
	string[] types;
	string   retType;

	this(ErrorInfo perror) {
		type  = NodeType.Extern;
		error = perror;
	}

	override string toString() {
		final switch (externType) {
			case ExternType.Callisto: return format("extern %s", func);
			case ExternType.Raw:      return format("extern raw %s", func);
			case ExternType.C: {
				string ret = format("extern C %s %s", retType, func);

				foreach (i, ref type ; types) {
					ret ~= format(" %s", type);
				}

				return ret ~ " end";
			}
		}
	}
}

class AddrNode : Node {
	string func;

	this(ErrorInfo perror) {
		type  = NodeType.Addr;
		error = perror;
	}

	override string toString() => format("&%s", func);
}

class ImplementNode : Node {
	string structure;
	string method;
	Node[] nodes;

	this(ErrorInfo perror) {
		type  = NodeType.Implement;
		error = perror;
	}

	override string toString() {
		string ret = format("implement %s %s\n", structure, method);

		foreach (ref node ; nodes) {
			ret ~= format("    %s\n", node.toString());
		}

		return ret ~ "end";
	}
}

class SetNode : Node {
	string var;

	this(ErrorInfo perror) {
		type  = NodeType.Set;
		error = perror;
	}

	override string toString() => format("-> %s", var);
}

class ParserError : Exception {
	this() {
		super("", "", 0);
	}
}

class Parser {
	Token[]  tokens;
	size_t   i;
	Node[]   nodes;
	NodeType parsing;

	this() {
		
	}

	ErrorInfo GetError() {
		return ErrorInfo(
			tokens[i].file, tokens[i].line, tokens[i].col, tokens[i].contents.length
		);
	}

	void Error(Char, A...)(in Char[] fmt, A args) {
		ErrorBegin(GetError());
		stderr.writeln(format(fmt, args));
		PrintErrorLine(GetError());
		throw new ParserError();
	}

	void Next() {
		++ i;

		if (i >= tokens.length) {
			-- i;
			Error("Unexpected EOF while parsing %s", parsing);
		}
	}

	void Expect(TokenType type) {
		if (tokens[i].type != type) {
			Error("Expected %s, got %s while parsing %s", type, tokens[i].type, parsing);
		}
	}

	bool IsIdentifier(string identifier) {
		return
			(tokens[i].type == TokenType.Identifier) &&
			(tokens[i].contents == identifier);
	}

	Node ParseFuncDef(bool inline) {
		auto ret   = new FuncDefNode(GetError());
		ret.inline = inline;
		parsing    = NodeType.FuncDef;

		Next();
		Expect(TokenType.Identifier);

		if (tokens[i].contents == "raw") {
			ret.raw = true;
			Next();
			Expect(TokenType.Identifier);
		}

		ret.name = tokens[i].contents;

		Next();

		while (!IsIdentifier("begin")) {
			Expect(TokenType.Identifier);
			ret.paramTypes ~= tokens[i].contents;
			Next();
			Expect(TokenType.Identifier);
			ret.params ~= tokens[i].contents;
			Next();
		}

		Next();

		while (true) {
			if (
				(tokens[i].type == TokenType.Identifier) &&
				(tokens[i].contents == "end")
			) {
				break;
			}

			ret.nodes ~= ParseStatement();

			if (ret.nodes[$ - 1].type == NodeType.FuncDef) {
				Error("Function definitions can't be nested");
			}

			Next();
		}

		return ret;
	}

	Node ParseInclude() {
		auto ret = new IncludeNode(GetError());
		parsing  = NodeType.Include;

		Next();
		Expect(TokenType.String);

		ret.path = tokens[i].contents;
		return ret;
	}

	Node ParseAsm() {
		auto ret = new AsmNode(GetError());
		parsing  = NodeType.Asm;
		Next();

		while (true) {
			switch (tokens[i].type) {
				case TokenType.Identifier: {
					if (tokens[i].contents != "end") {
						Error("Unexpected identifier");
					}

					goto end;
				}
				case TokenType.String: {
					ret.code ~= tokens[i].contents ~ '\n';
					break;
				}
				default: {
					Error("Unexpected %s", tokens[i].type);
				}
			}
			Next();
		}

		end:
		return ret;
	}

	Node ParseIf() {
		auto ret       = new IfNode(GetError());
		ret.condition ~= new Node[](0);
		ret.doIf      ~= new Node[](0);
		parsing        = NodeType.If;
		Next();

		while (true) {
			parsing = NodeType.If;
			if (!ret.hasElse) {
				while (true) {
					parsing = NodeType.If;
					if (
						(tokens[i].type == TokenType.Identifier) &&
						(tokens[i].contents == "then")
					) {
						break;
					}

					ret.condition[$ - 1] ~= ParseStatement();
					Next();
				}
			}

			Next();

			while (true) {
				parsing = NodeType.If;
				if (
					(tokens[i].type == TokenType.Identifier) &&
					(tokens[i].contents == "elseif")
				) {
					ret.condition ~= new Node[](0);
					ret.doIf      ~= new Node[](0);
					Next();
					break;
				}
				if (
					(tokens[i].type == TokenType.Identifier) &&
					(tokens[i].contents == "else")
				) {
					ret.hasElse = true;

					Next();
					while (true) {
						if (
							(tokens[i].type == TokenType.Identifier) &&
							(tokens[i].contents == "end")
						) {
							return ret;
						}

						ret.doElse ~= ParseStatement();
						Next();
					}
				}
				if (
					(tokens[i].type == TokenType.Identifier) &&
					(tokens[i].contents == "end")
				) {
					return ret;
				}

				ret.doIf[$ - 1] ~= ParseStatement();
				Next();
			}
		}

		assert(0);
	}

	Node ParseWhile() {
		auto ret = new WhileNode(GetError());
		parsing  = NodeType.While;
		Next();

		while (true) {
			if (
				(tokens[i].type == TokenType.Identifier) &&
				(tokens[i].contents == "do")
			) {
				break;
			}

			ret.condition ~= ParseStatement();
			Next();
			parsing = NodeType.While;
		}

		Next();

		while (true) {
			parsing = NodeType.While;
			if (
				(tokens[i].type == TokenType.Identifier) &&
				(tokens[i].contents == "end")
			) {
				break;
			}

			ret.doWhile ~= ParseStatement();
			Next();
			parsing  = NodeType.While;
		}

		return ret;
	}

	Node ParseLet() {
		auto ret = new LetNode(GetError());
		parsing  = NodeType.Let;

		Next();
		Expect(TokenType.Identifier);

		if (tokens[i].contents == "array") {
			Next();
			Expect(TokenType.Integer);

			ret.array     = true;
			ret.arraySize = parse!size_t(tokens[i].contents);
			Next();
			Expect(TokenType.Identifier);
		}

		ret.varType = tokens[i].contents;
		Next();
		Expect(TokenType.Identifier);
		ret.name = tokens[i].contents;

		return ret;
	}

	Node ParseEnable() {
		auto ret = new EnableNode(GetError());
		parsing  = NodeType.Enable;

		Next();
		Expect(TokenType.Identifier);
		ret.ver = tokens[i].contents;

		return ret;
	}

	Node ParseRequires() {
		auto ret = new RequiresNode(GetError());
		parsing  = NodeType.Requires;

		Next();
		Expect(TokenType.Identifier);
		ret.ver = tokens[i].contents;

		return ret;
	}

	Node ParseArray() {
		auto ret = new ArrayNode(GetError());
		parsing  = NodeType.Array;

		switch (tokens[i].contents) {
			case "c": {
				ret.constant = true;
				break;
			}
			case "": break;
			default: {
				Error("Unknown attribute '%s'", tokens[i].contents);
			}
		}

		const NodeType[] allowedNodes = [
			NodeType.Word, NodeType.Integer
		];

		Next();
		Expect(TokenType.Identifier);
		ret.arrayType = tokens[i].contents;
		Next();

		while (tokens[i].type != TokenType.RSquare) {
			parsing       = NodeType.Array;
			ret.elements ~= ParseStatement();
			Next();
		}

		return ret;
	}

	Node ParseString() {
		auto ret = new StringNode(GetError());
		parsing  = NodeType.String;

		switch (tokens[i].extra) {
			case "c": {
				ret.constant = true;
				break;
			}
			case "": break;
			default: {
				Error("Invalid string type: '%s'", tokens[i].extra);
			}
		}

		ret.value = tokens[i].contents;
		return ret;
	}

	Node ParseStruct() {
		auto ret = new StructNode(GetError());
		parsing  = NodeType.Struct;

		Next();
		Expect(TokenType.Identifier);
		ret.name = tokens[i].contents;
		Next();

		if ((tokens[i].type == TokenType.Identifier) && (tokens[i].contents == ":")) {
			Next();
			Expect(TokenType.Identifier);

			ret.inherits     = true;
			ret.inheritsFrom = tokens[i].contents;
			Next();
		}

		while (true) {
			if (
				(tokens[i].type == TokenType.Identifier) &&
				(tokens[i].contents == "end")
			) {
				break;
			}

			/*Expect(TokenType.Identifier);
			ret.types ~= tokens[i].contents;
			Next();
			Expect(TokenType.Identifier);
			ret.names ~= tokens[i].contents;
			Next();*/

			StructMember member;
			Expect(TokenType.Identifier);

			if (tokens[i].contents == "array") {
				Next();
				Expect(TokenType.Integer);
				member.array = true;
				member.size  = parse!size_t(tokens[i].contents);

				Next();
				Expect(TokenType.Identifier);
			}
			
			member.type = tokens[i].contents;
			Next();
			Expect(TokenType.Identifier);
			member.name = tokens[i].contents;

			ret.members ~= member;

			Next();
			Expect(TokenType.Identifier);
		}

		return ret;
	}

	Node ParseVersion() {
		auto ret = new VersionNode(GetError());
		parsing  = NodeType.Version;

		Next();
		Expect(TokenType.Identifier);

		if (tokens[i].contents == "not") {
			ret.not = true;
			Next();
			Expect(TokenType.Identifier);
		}

		ret.ver = tokens[i].contents;
		Next();

		while (true) {
			if (
				(tokens[i].type == TokenType.Identifier) &&
				(tokens[i].contents == "end")
			) {
				break;
			}

			ret.block ~= ParseStatement();
			Next();
		}

		return ret;
	}

	Node ParseConst() {
		auto ret = new ConstNode(GetError());
		parsing  = NodeType.Const;

		Next();
		Expect(TokenType.Identifier);
		ret.name = tokens[i].contents;

		Next();
		Expect(TokenType.Integer);
		ret.value = parse!long(tokens[i].contents);

		return ret;
	}

	Node ParseEnum() {
		auto ret = new EnumNode(GetError());
		parsing  = NodeType.Enum;

		Next();
		Expect(TokenType.Identifier);
		ret.name = tokens[i].contents;
		ret.enumType = "cell";

		Next();
		Expect(TokenType.Identifier);

		if (tokens[i].contents == ":") {
			Next();
			Expect(TokenType.Identifier);
			ret.enumType = tokens[i].contents;

			Next();
			Expect(TokenType.Identifier);
		}

		while (true) {
			if (tokens[i].contents == "end") break;

			ret.names ~= tokens[i].contents;
			Next();
			Expect(TokenType.Identifier);

			if (tokens[i].contents == "=") {
				Next();
				Expect(TokenType.Integer);

				ret.values ~= parse!long(tokens[i].contents);
				Next();
				Expect(TokenType.Identifier);
			}
			else {
				ret.values ~= ret.values.empty()? 0 : ret.values[$ - 1] + 1;
			}
		}

		return ret;
	}

	Node ParseRestrict() {
		auto ret = new RestrictNode(GetError());
		parsing  = NodeType.Restrict;

		Next();
		Expect(TokenType.Identifier);
		ret.ver = tokens[i].contents;

		return ret;
	}

	Node ParseUnion() {
		auto ret = new UnionNode(GetError());
		parsing  = NodeType.Union;

		Next();
		Expect(TokenType.Identifier);
		ret.name = tokens[i].contents;
		Next();
		Expect(TokenType.Identifier);

		while (true) {
			if ((tokens[i].type == TokenType.Identifier) && (tokens[i].contents == "end")) {
				break;
			}

			ret.types ~= tokens[i].contents;
			Next();
			Expect(TokenType.Identifier);
		}

		return ret;
	}

	Node ParseAlias() {
		auto ret = new AliasNode(GetError());
		parsing  = NodeType.Alias;

		Next();
		Expect(TokenType.Identifier);

		if (tokens[i].contents == "overwrite") {
			ret.overwrite = true;
			Next();
			Expect(TokenType.Identifier);
		}

		ret.to = tokens[i].contents;

		Next();
		Expect(TokenType.Identifier);
		ret.from = tokens[i].contents;

		return ret;
	}

	Node ParseExtern() {
		auto ret = new ExternNode(GetError());
		parsing  = NodeType.Extern;

		Next();
		Expect(TokenType.Identifier);

		if (tokens[i].contents == "raw") {
			ret.externType = ExternType.Raw;

			Next();
			Expect(TokenType.Identifier);
			ret.func = tokens[i].contents;
		}
		else if (tokens[i].contents == "C") {
			ret.externType = ExternType.C;

			Next();
			Expect(TokenType.Identifier);
			ret.retType = tokens[i].contents;

			Next();
			Expect(TokenType.Identifier);
			ret.func = tokens[i].contents;

			while (true) {
				Next();
				Expect(TokenType.Identifier);

				if (tokens[i].contents == "end") {
					break;
				}

				ret.types ~= tokens[i].contents;
			}
		}
		else {
			ret.externType = ExternType.Callisto;
			ret.func       = tokens[i].contents;
		}

		return ret;
	}

	Node ParseAddr() {
		auto ret = new AddrNode(GetError());
		parsing  = NodeType.Addr;

		Next();
		Expect(TokenType.Identifier);
		ret.func = tokens[i].contents;

		return ret;
	}

	Node ParseImplement() {
		auto ret = new ImplementNode(GetError());
		parsing  = NodeType.Implement;

		Next();
		Expect(TokenType.Identifier);
		ret.structure = tokens[i].contents;

		Next();
		Expect(TokenType.Identifier);
		ret.method = tokens[i].contents;

		Next();
		while (true) {
			if (
				(tokens[i].type == TokenType.Identifier) &&
				(tokens[i].contents == "end")
			) {
				break;
			}

			ret.nodes ~= ParseStatement();

			if (ret.nodes[$ - 1].type == NodeType.FuncDef) {
				Error("Function definitions can't be nested");
			}

			Next();
		}

		return ret;
	}

	Node ParseSet() {
		auto ret = new SetNode(GetError());
		parsing  = NodeType.Set;

		Next();
		Expect(TokenType.Identifier);
		ret.var = tokens[i].contents;

		return ret;
	}

	Node ParseStatement() {
		switch (tokens[i].type) {
			case TokenType.Integer: {
				return new IntegerNode(GetError(), parse!long(tokens[i].contents));
			}
			case TokenType.Identifier: {
				switch (tokens[i].contents) {
					case "func":       return ParseFuncDef(false);
					case "inline":     return ParseFuncDef(true);
					case "include":    return ParseInclude();
					case "asm":        return ParseAsm();
					case "if":         return ParseIf();
					case "while":      return ParseWhile();
					case "let":        return ParseLet();
					case "enable":     return ParseEnable();
					case "requires":   return ParseRequires();
					case "struct":     return ParseStruct();
					case "version":    return ParseVersion();
					case "const":      return ParseConst();
					case "enum":       return ParseEnum();
					case "restrict":   return ParseRestrict();
					case "union":      return ParseUnion();
					case "alias":      return ParseAlias();
					case "extern":     return ParseExtern();
					case "implement":  return ParseImplement();
					case "->":         return ParseSet();
					default: return new WordNode(GetError(), tokens[i].contents);
				}
			}
			case TokenType.LSquare:   return ParseArray();
			case TokenType.String:    return ParseString();
			case TokenType.Ampersand: return ParseAddr();
			default: {
				Error("Unexpected %s", tokens[i].type);
			}
		}

		assert(0);
	}

	void Parse() {
		for (i = 0; i < tokens.length; ++ i) {
			nodes ~= ParseStatement();
		}
	}
}
