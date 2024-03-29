module callisto.parser;

import std.conv;
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
	Implements,
	Feature,
	Requires,
	Version,
	Array,
	String
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
		type  = NodeType.Integer;
		value = pvalue;
	}

	override string toString() => format("%d", value);
}

class FuncDefNode : Node {
	string name;
	Node[] nodes;
	bool   inline;

	this(ErrorInfo perror) {
		type  = NodeType.FuncDef;
		error = perror;
	}

	override string toString() {
		string ret = format("func %s\n", name);

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

	override string toString() => format("include \"path\"", path);
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
}

class ImplementsNode : Node {
	string feature;
	Node   node;

	this(ErrorInfo perror) {
		type  = NodeType.Implements;
		error = perror;
	}
}

class FeatureNode : Node {
	string feature;

	this(ErrorInfo perror) {
		type  = NodeType.Feature;
		error = perror;
	}
}

class RequiresNode : Node {
	string feature;

	this(ErrorInfo perror) {
		type  = NodeType.Requires;
		error = perror;
	}
}

class VersionNode : Node {
	string ver;
	Node[] block;

	this(ErrorInfo perror) {
		type  = NodeType.Version;
		error = perror;
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
}

class StringNode : Node {
	string value;
	bool   constant;

	this(ErrorInfo perror) {
		type  = NodeType.String;
		error = perror;
	}
}

class ParserError : Exception {
	this() {
		super("", "", 0);
	}
}

class Parser {
	Token[] tokens;
	size_t  i;
	Node[]  nodes;

	this() {
		
	}

	ErrorInfo GetError() {
		return ErrorInfo(tokens[i].file, tokens[i].line, tokens[i].col);
	}

	void Error(Char, A...)(in Char[] fmt, A args) {
		ErrorBegin(GetError());
		stderr.writeln(format(fmt, args));
		throw new ParserError();
	}

	void Next() {
		++ i;

		if (i >= tokens.length) {
			-- i;
			Error("Unexpected EOF");
		}
	}

	void Expect(TokenType type) {
		if (tokens[i].type != type) {
			Error("Expected %s, got %s", type, tokens[i].type);
		}
	}

	Node ParseFuncDef(bool inline) {
		auto ret   = new FuncDefNode(GetError());
		ret.inline = inline;

		Next();
		Expect(TokenType.Identifier);
		ret.name = tokens[i].contents;

		Next();
		Expect(TokenType.Identifier);
		if (tokens[i].contents != "begin") {
			Error("Expected begin keyword"); // TODO: add parameters
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

		Next();
		Expect(TokenType.String);

		ret.path = tokens[i].contents;
		return ret;
	}

	Node ParseAsm() {
		auto ret = new AsmNode(GetError());
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
		Next();

		while (true) {
			if (!ret.hasElse) {
				while (true) {
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
		}

		Next();

		while (true) {
			if (
				(tokens[i].type == TokenType.Identifier) &&
				(tokens[i].contents == "end")
			) {
				break;
			}

			ret.doWhile ~= ParseStatement();
			Next();
		}

		return ret;
	}

	Node ParseLet() {
		auto ret = new LetNode(GetError());

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

	Node ParseImplements() {
		auto ret = new ImplementsNode(GetError());

		Next();
		Expect(TokenType.Identifier);
		ret.feature = tokens[i].contents;

		Next();
		ret.node = ParseStatement();

		return ret;
	}

	Node ParseFeature() {
		auto ret = new FeatureNode(GetError());

		Next();
		Expect(TokenType.Identifier);
		ret.feature = tokens[i].contents;

		return ret;
	}

	Node ParseRequires() {
		auto ret = new RequiresNode(GetError());

		Next();
		Expect(TokenType.Identifier);
		ret.feature = tokens[i].contents;

		return ret;
	}

	Node ParseArray() {
		auto ret = new ArrayNode(GetError());

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
			ret.elements ~= ParseStatement();
			Next();
		}

		return ret;
	}

	Node ParseString() {
		auto ret = new StringNode(GetError());

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
					case "implements": return ParseImplements();
					case "feature":    return ParseFeature();
					case "requires":   return ParseRequires();
					case "array":      return ParseArray();
					default: return new WordNode(GetError(), tokens[i].contents);
				}
			}
			case TokenType.LSquare: return ParseArray();
			case TokenType.String:  return ParseString();
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
