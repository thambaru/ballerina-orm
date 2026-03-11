import thambaru/bal_orm.orm_cli;

# Runs the `bal orm` CLI tool.
#
# Delegates to `orm_cli:runCli`, which dispatches on the first argument:
#   init | migrate (dev|deploy|reset|status) | db (push|pull) | generate | help
#
# + args - CLI arguments passed after `--` when invoking `bal run . -- <args>`
# + return - error propagated from the selected command handler, if any
public function main(string... args) returns error? {
    check orm_cli:runCli(args);
}

# Returns the string `Hello` with the input string name.
#
# + name - name as a string or nil
# + return - "Hello, " with the input string name
public function hello(string? name) returns string {
    if name !is () {
        return string `Hello, ${name}`;
    }
    return "Hello, World!";
}
