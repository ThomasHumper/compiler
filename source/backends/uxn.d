module callisto.backends.uxn;

import std.conv;
import std.stdio;
import std.range;
import std.format;
import std.algorithm;
import callisto.util;
import callisto.error;
import callisto.parser;
import callisto.compiler;
import callisto.language;

private struct Word {
	bool   raw;
	bool   inline;
	Node[] inlineNodes;
}

private struct StructEntry {
	Type   type;
	string name;
	bool   array;
	size_t size;
}

private struct Type {
	string        name;
	ulong         size;
	bool          isStruct;
	StructEntry[] structure;
	bool          hasInit;
	bool          hasDeinit;
}

private struct Variable {
	string name;
	Type   type;
	uint   offset; // SP + offset to access
	bool   array;
	ulong  arraySize;

	size_t Size() => array? arraySize * type.size : type.size;
}

private struct Global {
	Type  type;
	bool  array;
	ulong arraySize;

	size_t Size() => array? arraySize * type.size : type.size;
}

private struct Constant {
	Node value;
}

private struct Array {
	string[] values;
	Type     type;
	bool     global;

	size_t Size() => type.size * values.length;
}

class BackendUXN : CompilerBackend {
	Word[string]     words;
	uint             blockCounter; // used for block statements
	Type[]           types;
	Variable[]       variables;
	Global[string]   globals;
	Constant[string] consts;
	bool             inScope;
	Array[]          arrays;
	string           thisFunc;
	bool             inWhile;
	uint             currentLoop;

	this() {
		types ~= Type("u8",    1);
		types ~= Type("i8",    1);
		types ~= Type("u16",   2);
		types ~= Type("i16",   2);
		types ~= Type("addr",  2);
		types ~= Type("size",  2);
		types ~= Type("usize", 2);
		types ~= Type("cell",  2);

		// built in structs
		types ~= Type("Array", 6, true, [
			StructEntry(GetType("usize"), "length"),
			StructEntry(GetType("usize"), "memberSize"),
			StructEntry(GetType("addr"),  "elements")
		]);
		NewConst("Array.length",     0);
		NewConst("Array.memberSize", 2);
		NewConst("Array.elements",   4);
		NewConst("Array.sizeof",     2 * 3);

		foreach (name, ref type ; types) {
			NewConst(format("%s.sizeof", name), cast(long) type.size);
		}
	}

	override string[] GetVersions() => [
		// platform
		"UXN", "BigEndian", "16Bit",
		// features
		"IO"
	];

	override string[] FinalCommands() => [
		format("mv %s %s.tal", compiler.outFile, compiler.outFile),
		format("uxnasm %s.tal %s", compiler.outFile, compiler.outFile),
		keepAssembly? "" : format("rm %s.tal", compiler.outFile)
	];

	override long MaxInt() => 0xFFFF;

	override string DefaultHeader() => "
		|10 @Console &vector $2 &read $1 &pad $5 &write $1 &error $1
	";

	override bool HandleOption(string opt, ref string[] versions) => false;

	override void NewConst(string name, long value, ErrorInfo error = ErrorInfo.init) {
		consts[name] = Constant(new IntegerNode(error, value));
	}

	bool VariableExists(string name) => variables.any!(v => v.name == name);

	Variable GetVariable(string name) {
		foreach (ref var ; variables) {
			if (var.name == name) {
				return var;
			}
		}

		assert(0);
	}

	bool TypeExists(string name) => types.any!(v => v.name == name);

	Type GetType(string name) {
		foreach (ref type ; types) {
			if (type.name == name) {
				return type;
			}
		}

		assert(0);
	}

	void SetType(string name, Type ptype) {
		foreach (i, ref type ; types) {
			if (type.name == name) {
				types[i] = ptype;
				return;
			}
		}

		assert(0);
	}

	size_t GetStackSize() {
		// old
		//return variables.empty()? 0 : variables[0].offset + variables[0].type.size;

		size_t size;
		foreach (ref var ; variables) {
			size += var.Size();
		}

		return size;
	}

	override void BeginMain() {
		output ~= "@calmain\n";

		foreach (name, global ; globals) {
			if (global.type.hasInit) {
				output ~= format(";global_%s\n", name.Sanitise());
				output ~= format("type_init_%s\n", global.type.name.Sanitise());
			}
		}
	}

	void CallFunction(string name) {
		auto word = words[name];

		if (word.inline) {
			foreach (inode ; word.inlineNodes) {
				compiler.CompileNode(inode);
			}
		}
		else {
			if (word.raw) {
				output ~= format("%s\n", name);
			}
			else {
				output ~= format("func__%s\n", name.Sanitise());
			}
		}
	}

	override void Init() {
		output ~= "|0 @vsp $2 @arraySrc $2 @arrayDest $2\n";
		output ~= "|100\n";
		output ~= "@on-reset\n";
		output ~= "    #ffff .vsp STZ2\n";
		output ~= "    calmain\n";
		output ~= "    BRK\n";
	}

	override void End() {
		// call destructors
		foreach (name, global ; globals) {
			if (global.type.hasDeinit) {
				output ~= format(";global_%s\n", name.Sanitise());
				output ~= format("type_deinit_%s\n", global.type.name.Sanitise());
			}
		}

		output ~= "JMP2r\n";

		foreach (name, var ; globals) {
			output ~= format("@global_%s", name.Sanitise());

			foreach (i ; 0 .. var.Size()) {
				output ~= " 00";
			}

			output ~= "\n";
		}

		foreach (i, ref array ; arrays) {
			output ~= format("@array_%d ", i);

			foreach (j, ref element ; array.values) {
				output ~= element ~ (j == array.values.length - 1? "" : " ");
			}

			output ~= '\n';

			if (array.global) {
				output ~= format(
					"@array_%d_meta %.4x %.4x =array_%d\n", i,
					array.values.length,
					array.type.size,
					i
				);
			}
		}

		// pad for the stack
		output ~= "|e0000\n";
	}

	override void CompileWord(WordNode node) {
		if (node.name in words) {
			auto word = words[node.name];

			if (word.inline) {
				foreach (inode ; word.inlineNodes) {
					compiler.CompileNode(inode);
				}
			}
			else {
				if (word.raw) {
					output ~= format("%s\n", node.name);
				}
				else {
					output ~= format("func__%s\n", node.name.Sanitise());
				}
			}
		}
		else if (VariableExists(node.name)) {
			auto var = GetVariable(node.name);

			if (var.type.isStruct) {
				Error(node.error, "Can't push value of struct");
			}

			if (var.offset == 0) {
				output ~= ".vsp LDZ2\n";
			}
			else {
				output ~= format(".vsp LDZ2 #%.4x ADD2\n", var.offset);
			}

			switch (var.type.size) {
				case 1: output ~= "LDA NIP\n"; break;
				case 2: output ~= "LDA2\n"; break;
				default: Error(node.error, "Bad variable type size");
			}
		}
		else if (node.name in globals) {
			auto var = globals[node.name];
			output ~= format(";global_%s\n", node.name.Sanitise());

			if (var.type.isStruct) {
				Error(node.error, "Can't push value of struct");
			}

			switch (var.type.size) {
				case 1: output ~= "LDA NIP\n"; break;
				case 2: output ~= "LDA2\n"; break;
				default: Error(node.error, "Bad variable type size");
			}
		}
		else if (node.name in consts) {
			auto value  = consts[node.name].value;
			value.error = node.error;

			compiler.CompileNode(consts[node.name].value);
		}
		else {
			Error(node.error, "Undefined identifier '%s'", node.name);
		}
	}

	override void CompileInteger(IntegerNode node) {
		if (node.value > 0xFFFF) {
			Error(node.error, "Value is too big for 16-bit target");
		}

		output ~= format("#%.4x\n", node.value);
	}

	override void CompileFuncDef(FuncDefNode node) {
		if ((node.name in words) || VariableExists(node.name)) {
			Error(node.error, "Function name '%s' already used", node.name);
		}
		if (Language.bannedNames.canFind(node.name)) {
			Error(node.error, "Name '%s' can't be used", node.name);
		}

		thisFunc = node.name;

		if (node.inline) {
			words[node.name] = Word(false, true, node.nodes);
		}
		else {
			assert(!inScope);
			inScope = true;

			words[node.name] = Word(node.raw, false, []);

			string symbol =
				node.raw? node.name : format("func__%s", node.name.Sanitise());

			output ~= format("@%s\n", symbol);

			// allocate parameters
			size_t paramSize = node.params.length * 2;
			foreach (ref type ; node.paramTypes) {
				if (!TypeExists(type)) {
					Error(node.error, "Type '%s' doesn't exist", type);
				}
				if (GetType(type).isStruct) {
					Error(node.error, "Structures cannot be used in function parameters");
				}
			}
			if (paramSize > 0) {
				output ~= format(".vsp LDZ2 #%.4x SUB2 .vsp STZ2\n", paramSize);
				foreach (ref var ; variables) {
					var.offset += paramSize;
				}

				size_t offset;
				foreach (i, ref type ; node.paramTypes) {
					auto     param = node.params[i];
					Variable var;

					var.name      = param;
					var.type      = GetType(type);
					var.offset    = cast(uint) offset;
					offset       += var.Size();
					variables    ~= var;
				}

				// copy all parameters
				foreach_reverse (ref param ; node.params) {
					auto setNode = new SetNode(node.error);
					setNode.var  = param;
					CompileSet(setNode);
				}
			}

			foreach (ref inode ; node.nodes) {
				compiler.CompileNode(inode);
			}

			size_t scopeSize;
			foreach (ref var ; variables) {
				scopeSize += var.Size();
				
				if (var.type.hasDeinit) {
					output ~= format(".vsp LDZ2 #.2x ADD2", var.offset);
					output ~= format("type_deinit_%s\n", Sanitise(var.type.name));
				}
			}
			//output ~= format(".vsp LDZ2 #%.4x ADD2 .vsp STZ2\n", scopeSize);
			if (scopeSize > 0) {
				output ~= ".vsp LDZ2 ";

				switch (scopeSize) {
					case 1:  output ~= "INC2 "; break;
					case 2:  output ~= "INC2 INC2 "; break;
					case 3:  output ~= "INC2 INC2 INC2 "; break;
					default: output ~= format("#%.4x ADD2 ", scopeSize); break;
				}

				output ~= ".vsp STZ2\n";
			}

			output    ~= "JMP2r\n";
			variables  = [];
			inScope    = false;
		}
	}

	override void CompileIf(IfNode node) {
		++ blockCounter;
		auto blockNum = blockCounter;
		uint condCounter;

		foreach (i, ref condition ; node.condition) {
			foreach (ref inode ; condition) {
				compiler.CompileNode(inode);
			}
			output ~= format("#0000 EQU2 ;if_%d_%d JCN2\n", blockNum, condCounter + 1);

			// create scope
			auto oldVars = variables.dup;
			auto oldSize = GetStackSize();

			foreach (ref inode ; node.doIf[i]) {
				compiler.CompileNode(inode);
			}

			// remove scope
			foreach (ref var ; variables) {
				if (oldVars.canFind(var)) continue;
				if (!var.type.hasDeinit)  continue;

				output ~= format(".vsp LDZ2 #.2x ADD2", var.offset);
				output ~= format("type_deinit_%s\n", Sanitise(var.type.name));
			}
			if (GetStackSize() - oldSize > 0) {
				output ~= format(
					".vsp LDZ2 #%.4x ADD .vsp STZ2\n", GetStackSize() - oldSize
				);
			}
			variables = oldVars;

			output ~= format(";if_%d_end JMP2\n", blockNum);

			++ condCounter;
			output ~= format("@if_%d_%d\n", blockNum, condCounter);
		}

		if (node.hasElse) {
			// create scope
			auto oldVars = variables.dup;
			auto oldSize = GetStackSize();

			foreach (ref inode ; node.doElse) {
				compiler.CompileNode(inode);
			}

			// remove scope
			foreach (ref var ; variables) {
				if (oldVars.canFind(var)) continue;
				if (!var.type.hasDeinit)  continue;

				output ~= format(".vsp LDZ2 #.2x ADD2", var.offset);
				output ~= format("type_deinit_%s\n", Sanitise(var.type.name));
			}
			if (GetStackSize() - oldSize > 0) {
				output ~= format(
					".vsp LDZ2 #%.4x ADD .vsp STZ2\n", GetStackSize() - oldSize
				);
			}
			variables = oldVars;
		}

		output ~= format("@if_%d_end\n", blockNum);
	}

	override void CompileWhile(WhileNode node) {
		++ blockCounter;
		uint blockNum = blockCounter;
		currentLoop   = blockNum;

		output ~= format(";while_%d_condition JMP2\n", blockNum);
		output ~= format("@while_%d\n", blockNum);

		// make scope
		auto oldVars = variables.dup;
		auto oldSize = GetStackSize();

		foreach (ref inode ; node.doWhile) {
			inWhile = true;
			compiler.CompileNode(inode);

			currentLoop = blockNum;
		}

		// remove scope
		output ~= format("@while_%d_next\n", blockNum);
		foreach (ref var ; variables) {
			if (oldVars.canFind(var)) continue;
			if (!var.type.hasDeinit)  continue;

			output ~= format(".vsp LDZ2 #.2x ADD2", var.offset);
			output ~= format("type_deinit_%s\n", Sanitise(var.type.name));
		}
		if (GetStackSize() - oldSize > 0) {
			output ~= format(
				".vsp LDZ2 #%.4x ADD .vsp STZ2\n", GetStackSize() - oldSize
			);
		}
		variables = oldVars;

		inWhile = false;

		output ~= format("@while_%d_condition\n", blockNum);
		
		foreach (ref inode ; node.condition) {
			compiler.CompileNode(inode);
		}

		output ~= "#0000 NEQ2\n";
		output ~= format(";while_%d JCN2\n", blockNum);
		output ~= format("@while_%d_end\n", blockNum);
	}

	override void CompileLet(LetNode node) {
		if (!TypeExists(node.varType)) {
			Error(node.error, "Undefined type '%s'", node.varType);
		}
		if (VariableExists(node.name) || (node.name in words)) {
			Error(node.error, "Variable name '%s' already used", node.name);
		}
		if (Language.bannedNames.canFind(node.name)) {
			Error(node.error, "Name '%s' can't be used", node.name);
		}

		if (inScope) {
			Variable var;
			var.name      = node.name;
			var.type      = GetType(node.varType);
			var.offset    = 0;
			var.array     = node.array;
			var.arraySize = node.arraySize;

			foreach (ref ivar ; variables) {
				ivar.offset += var.Size();
			}

			variables ~= var;

			output ~= format(".vsp LDZ2 #%.4x SUB2 .vsp STZ2\n", var.Size());

			if (var.Size() == 1) {
				output ~= format("#00 .vsp LDZ2 STA\n");
			}
			else if (var.Size() == 2) {
				output ~= format("#0000 .vsp LDZ2 STA2\n");
			}

			if (var.type.hasInit) {
				output ~= format(".vsp LDZ2 type_init_%s\n", Sanitise(var.type.name));
			}
		}
		else {
			Global global;
			global.type        = GetType(node.varType);
			global.array       = node.array;
			global.arraySize   = node.arraySize;
			globals[node.name] = global;
		}
	}

	override void CompileArray(ArrayNode node) {
		Array array;

		if (!TypeExists(node.arrayType)) {
			Error(node.error, "Type '%s' doesn't exist", node.arrayType);
		}

		array.type = GetType(node.arrayType);

		foreach (ref elem ; node.elements) {
			switch (elem.type) {
				case NodeType.Integer: {
					auto node2    = cast(IntegerNode) elem;

					//array.values ~= node2.value.text();
					final switch (array.type.size) {
						case 1: array.values ~= format("%.2x", node2.value); break;
						case 2: array.values ~= format("%.4x", node2.value); break;
					}
					break;
				}
				default: {
					Error(elem.error, "Type '%s' can't be used in array literal");
				}
			}
		}
		array.global  = !inScope || node.constant;
		arrays       ~= array;

		if (!inScope || node.constant) {
			output ~= format(";array_%d_meta\n", arrays.length - 1);
		}
		else {
			// allocate a copy of the array
			output ~= format(".vsp LDZ2 #%.4x SUB2 .vsp STZ2\n", array.Size());

			// copy array contents
			output ~= format(";array_%d .arraySrc STZ2\n", arrays.length - 1);
			output ~= ".vsp LDZ2 .arrayDest STZ2\n";
			output ~= format("#%.4x\n", array.Size());
			output ~= format("@copy_loop_%d\n", arrays.length - 1);
			output ~= ".arraySrc LDZ2 LDA .arrayDest LDZ2 STA\n";
			output ~= ".arraySrc LDZ2 INC2 .arraySrc STZ2\n";
			output ~= ".arrayDest LDZ2 INC2 .arrayDest STZ2\n";
			output ~= format("#0001 SUB2 DUP2 #0000 NEQ2 ,copy_loop_%d JCN\n", arrays.length - 1);

			Variable var;
			var.type      = array.type;
			var.offset    = 0;
			var.array     = true;
			var.arraySize = array.values.length;

			foreach (ref var2 ; variables) {
				var2.offset += var.Size();
			}

			variables ~= var;

			// create metadata variable
			var.type   = GetType("Array");
			var.offset = 0;
			var.array  = false;

			foreach (ref var2 ; variables) {
				var2.offset += var.Size();
			}

			variables ~= var;

			// save array address for later
			output ~= ".vsp LDZ2\n";
			// allocate metadata
			output ~= format(".vsp LDZ2 #%.4x SUB2 .vsp STZ2\n", 2 * 3);
			// length
			output ~= format("#%.4x .vsp LDZ2 STA2\n", array.values.length);
			// member size
			output ~= format("#%.4x .vsp LDZ2 INC2 INC2 STA2\n", array.type.size);
			// elements
			output ~= ".vsp LDZ2 #0004 ADD2 STA2\n";

			// push metadata address
			output ~= ".vsp LDZ2\n";
		}
	}

	override void CompileString(StringNode node) {
		auto arrayNode = new ArrayNode(node.error);

		arrayNode.arrayType = "u8";
		arrayNode.constant  = node.constant;

		foreach (ref ch ; node.value) {
			arrayNode.elements ~= new IntegerNode(node.error, cast(long) ch);
		}

		CompileArray(arrayNode);
	}

	override void CompileStruct(StructNode node) {
		size_t offset;

		if (TypeExists(node.name)) {
			Error(node.error, "Type '%s' defined multiple times", node.name);
		}

		StructEntry[] entries;
		string[]      members;

		if (node.inherits) {
			if (!TypeExists(node.inheritsFrom)) {
				Error(node.error, "Type '%s' doesn't exist", node.inheritsFrom);
			}

			if (!GetType(node.inheritsFrom).isStruct) {
				Error(node.error, "Type '%s' is not a structure", node.inheritsFrom);
			}

			entries = GetType(node.inheritsFrom).structure;

			foreach (ref member ; GetType(node.inheritsFrom).structure) {
				members ~= member.name;
			}
		}

		foreach (ref member ; node.members) {
			if (!TypeExists(member.type)) {
				Error(node.error, "Type '%s' doesn't exist", member.type);
			}
			if (members.canFind(member.name)) {
				Error(node.error, "Duplicate member '%s'", member.name);
			}

			entries ~= StructEntry(
				GetType(member.type), member.name, member.array, member.size
			);
			members ~= member.name;
		}

		foreach (ref member ; entries) {
			NewConst(format("%s.%s", node.name, member.name), offset);
			offset += member.array? member.type.size * member.size : member.type.size;
		}

		NewConst(format("%s.sizeof", node.name), offset);
		types ~= Type(node.name, offset, true, entries);
	}

	override void CompileReturn(WordNode node) {
		if (!inScope) {
			Error(node.error, "Return used outside of function");
		}

		size_t scopeSize;
		foreach (ref var ; variables) {
			scopeSize += var.Size();

			if (var.type.hasDeinit) {
				output ~= format(".vsp LDZ2 #.2x ADD2", var.offset);
				output ~= format("type_deinit_%s\n", Sanitise(var.type.name));
			}
		}
		output ~= format(".vsp LDZ2 #%.4x ADD2 .vsp STZ2\n", scopeSize);
		output ~= "JMP2r\n";
	}

	override void CompileConst(ConstNode node) {
		if (node.name in consts) {
			Error(node.error, "Constant '%s' already defined", node.name);
		}
		
		NewConst(node.name, node.value);
	}

	override void CompileEnum(EnumNode node) {
		if (!TypeExists(node.enumType)) {
			Error(node.error, "Enum base type '%s' doesn't exist", node.enumType);
		}
		if (TypeExists(node.name)) {
			Error(node.error, "Enum name is already used by type '%s'", node.enumType);
		}

		auto baseType  = GetType(node.enumType);
		baseType.name  = node.name;
		types         ~= baseType;

		foreach (i, ref name ; node.names) {
			NewConst(format("%s.%s", node.name, name), node.values[i]);
		}

		NewConst(format("%s.min", node.name), node.values.minElement());
		NewConst(format("%s.max", node.name), node.values.maxElement());
		NewConst(format("%s.sizeof", node.name), GetType(node.name).size);
	}

	override void CompileBreak(WordNode node) {
		if (!inWhile) {
			Error(node.error, "Not in while loop");
		}

		output ~= format(";while_%d_end JMP2\n", currentLoop);
	}

	override void CompileContinue(WordNode node) {
		if (!inWhile) {
			Error(node.error, "Not in while loop");
		}

		output ~= format(";while_%d_next JMP2\n", currentLoop);
	}

	override void CompileUnion(UnionNode node) {
		size_t maxSize = 0;

		if (TypeExists(node.name)) {
			Error(node.error, "Type '%s' already exists", node.name);
		}

		string[] unionTypes;

		foreach (ref type ; node.types) {
			if (unionTypes.canFind(type)) {
				Error(node.error, "Union type '%s' defined twice", type);
			}
			unionTypes ~= type;

			if (!TypeExists(type)) {
				Error(node.error, "Type '%s' doesn't exist", type);
			}

			if (GetType(type).size > maxSize) {
				maxSize = GetType(type).size;
			}
		}

		types ~= Type(node.name, maxSize);
		NewConst(format("%s.sizeof", node.name), cast(long) maxSize);
	}

	override void CompileAlias(AliasNode node) {
		if (!TypeExists(node.from)) {
			Error(node.error, "Type '%s' doesn't exist", node.from);
		}
		if (TypeExists(node.to) && !node.overwrite) {
			Error(node.error, "Type '%s' already defined", node.to);
		}

		auto baseType  = GetType(node.from);
		baseType.name  = node.to;
		types         ~= baseType;

		NewConst(format("%s.sizeof", node.to), cast(long) GetType(node.to).size);
	}

	override void CompileExtern(ExternNode node) {
		if (node.externType == ExternType.C) {
			Error(node.error, "This backend doesn't support C externs");
		}

		Word word;
		word.raw         = node.externType == ExternType.Raw;
		words[node.func] = word;
	}

	override void CompileCall(WordNode node) {
		output ~= "JSR2\n";
	}

	override void CompileAddr(AddrNode node) {
		if (node.func in words) {
			auto   word   = words[node.func];
			string symbol =
				word.raw? node.func : format("func__%s", node.func.Sanitise());

			output ~= format(";%s\n", symbol);
		}
		else if (VariableExists(node.func)) {
			auto var = GetVariable(node.func);

			if (var.offset == 0) {
				output ~= ".vsp LDZ2\n";
			}
			else {
				output ~= format(".vsp LDZ2 #%.4x ADD2\n", var.offset);
			}
		}
		else if (node.func in globals) {
			output ~= format(";global_%s\n", node.func.Sanitise());
		}
		else {
			Error(node.error, "Undefined identifier '%s'", node.func);
		}
	}

	override void CompileImplement(ImplementNode node) {
		if (!TypeExists(node.structure)) {
			Error(node.error, "Type '%s' doesn't exist", node.structure);
		}
		auto type = GetType(node.structure);

		string labelName;

		switch (node.method) {
			case "init": {
				if (GetType(node.structure).hasInit) {
					Error(node.error, "Already implemented in type");
				}

				type.hasInit = true;
				labelName = format("type_init_%s", Sanitise(node.structure));
				break;
			}
			case "deinit": {
				if (GetType(node.structure).hasDeinit) {
					Error(node.error, "Already implemented in type");
				}

				type.hasDeinit = true;
				labelName = format("type_deinit_%s", Sanitise(node.structure));
				break;
			}
			default: Error(node.error, "Unknown method '%s'", node.method);
		}

		SetType(type.name, type);

		assert(!inScope);
		inScope = true;

		output ~= format("@%s\n", labelName);

		foreach (ref inode ; node.nodes) {
			compiler.CompileNode(inode);
		}

		size_t scopeSize;
		foreach (ref var ; variables) {
			scopeSize += var.Size();

			if (var.type.hasDeinit) {
				output ~= format(".vsp LDZ2 #.2x ADD2", var.offset);
				output ~= format("type_deinit_%s\n", Sanitise(var.type.name));
			}
		}
		if (scopeSize > 0) {
			output ~= ".vsp LDZ2 ";

			switch (scopeSize) {
				case 1:  output ~= "INC2 "; break;
				case 2:  output ~= "INC2 INC2 "; break;
				case 3:  output ~= "INC2 INC2 INC2 "; break;
				default: output ~= format("#%.4x ADD2 ", scopeSize); break;
			}

			output ~= ".vsp STZ2\n";
		}

		output    ~= "JMP2r\n";
		inScope    = false;
		variables  = [];
	}

	override void CompileSet(SetNode node) {
		if (VariableExists(node.var)) {
			auto var = GetVariable(node.var);

			if (var.type.isStruct) {
				Error(node.error, "Can't set struct value");
			}

			if (var.offset == 0) {
				switch (var.type.size) {
					case 1: output ~= "NIP .vsp LDZ2 STA\n"; break;
					case 2: output ~= ".vsp LDZ2 STA2\n"; break;
					default: Error(node.error, "Bad variable type size");
				}
			}
			else {
				switch (var.type.size) {
					case 1: {
						output ~= format("NIP .vsp LDZ2 #%.4X ADD2 STA\n", var.offset);
						break;
					}
					case 2: {
						output ~= format(".vsp LDZ2 #%.4X ADD2 STA2\n", var.offset);
						break;
					}
					default: Error(node.error, "Bad variable type size");
				}
			}
		}
		else if (node.var in globals) {
			auto global = globals[node.var];

			if (global.type.isStruct) {
				Error(node.error, "Can't set struct value");
			}

			string symbol = format("global_%s", node.var.Sanitise());

			switch (global.type.size) {
				case 1: output ~= format("NIP ;%s STA\n", symbol); break;
				case 2: output ~= format(";%s STA2\n", symbol); break;
				default: Error(node.error, "Bad variable type size");
			}
		}
		else {
			Error(node.error, "Variable '%s' doesn't exist", node.var);
		}
	}
}
