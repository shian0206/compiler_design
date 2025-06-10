#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <algorithm> 
#include "symboltable.h"

#define MAX_SYMBOLS 100
#define MAX_NAME 256

// Function to create a new symbol table
SymbolTable* create_symbol_table(SymbolTable *parent) {
    SymbolTable *table = new SymbolTable(); 
    if (!table) {
        fprintf(stderr, "Error: Unable to allocate memory for symbol table.\n");
        exit(EXIT_FAILURE);
    }
    table->symbols.clear();
    table->parent = parent;
    return table;
}

// Function to insert a symbol into the current symbol table
int insert_symbol(SymbolTable *table, Symbol *symbol) {
    auto it = std::find_if(table->symbols.begin(), table->symbols.end(),
                           [symbol](const Symbol *s) { return s->name == symbol->name; });
    if (it != table->symbols.end()) {
        fprintf(stderr, "Error: Symbol '%s' already exists in the current scope.\n", symbol->name.c_str());
        return -1; 
    }

    symbol->is_global = table->isGlobal(); // Set the is_global flag
    table->symbols.push_back(symbol);

    return 0;
}

// Function to lookup a symbol in the current and parent symbol tables
Symbol* lookup_symbol(SymbolTable *table, string name, int search_parent) {
    SymbolTable *current_table = table;
    while (current_table) {
        auto it = std::find_if(current_table->symbols.begin(), current_table->symbols.end(),
                               [&name](const Symbol *symbol) { return symbol->name == name; });
        if (it != current_table->symbols.end()) {
            return *it; // Return the found symbol
        }
        if (!search_parent) {
            break; // Still break if only searching current scope and not found
        }
        current_table = current_table->parent;
    }
    return NULL;
}

// Function to delete the current symbol table and free memory
void delete_symbol_table(SymbolTable *table) {
    for (Symbol *symbol : table->symbols) {
        if (symbol->value) {
            delete symbol->value;
        }
        if (symbol->arr) {
            for (auto v : *(symbol->arr)) {
                delete v;
            }
            delete symbol->arr;
        }
        if (symbol->formal_parameters) {
            for (auto s : *(symbol->formal_parameters)) {
                delete s;
            }
            delete symbol->formal_parameters;
        }
        delete symbol;
    }
    table->symbols.clear();
    delete table;
}

// Function to print the symbol table for debugging
void dump_symbol_table(SymbolTable *table) {
    printf("Symbol Table:\n");
    for (const Symbol *symbol : table->symbols) {
        printf("Name: %s, Type: %s\n",
               symbol->name.c_str(),  toTypeString(symbol->type).c_str());
    }
}

SymbolValue* callFunction(Symbol* func, vector<SymbolValue*>* args) {
    SymbolValue* ret = new SymbolValue(_VAL, _INT, 0);
    if (func->value) {
        ret->dataType = func->value->dataType;
    } else {
        ret->dataType = _INT;
    }
    return ret;
}


string toTypeString(int t) {
    if (t == 0) {
        return "VAL";
    } else if (t == 1) {
        return "VAR";
    } else if (t == 2) {
        return "ARRAY";
    } else if (t == 3) {
        return "FUNCTION";
    }
    return "";
}

string toDataTypeString(int t) {
    if (t == _INT) {
        return "int";
    } else if (t == _FLOAT) {
        return "float";
    } else if (t == _STRING) {
        return "string";
    } else if (t == _BOOL) {
        return "bool";
    }
    return "";
}
