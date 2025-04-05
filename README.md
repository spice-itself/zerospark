# ZeroSpark - Minimalist Initialization Process in Zig

## Description

ZeroSpark is a simple initialization process (init system) written in the Zig programming language. It is designed to manage services in Linux systems, providing basic functionality:

- Starting services at system boot
- Monitoring the state of services
- Automatic restarting of services upon termination (if configured)

## Features

- Minimalist design
- Written in the modern Zig language
- Simple configuration via a text file
- Support for automatic service restarting
- Low resource consumption

## Requirements

- Linux system
- Zig (version 0.11.0 or newer)

## Installation

1. Ensure you have the Zig compiler installed
2. Clone the repository (if available)
3. Compile the project:
   ```sh
   zig build-exe zerospark.zig -O ReleaseSafe
   ```
4. Install the resulting binary as `/sbin/init` or use it as a user-space initialization process

## Configuration

Create a `init.conf` file in the working directory with service configurations. The file format is:

```
restart:command argument1 argument2 ...
no_restart:another_command
```

- `restart:` - the service will be automatically restarted upon termination
- `no_restart:` - the service will not be restarted upon termination

Example:
```
restart:/usr/sbin/sshd -D
no_restart:/usr/bin/my_service --config /etc/my.conf
restart:/usr/bin/nginx -g "daemon off;"
```

## Usage

1. Run `zerospark` as the init process (typically PID 1)
2. The program will automatically:
   - Read the configuration from `init.conf`
   - Start all specified services
   - Monitor their state
   - Restart services marked with `restart:` when they terminate

## Logging

The program outputs information about service states to standard output/system log:
- Service startups
- Service terminations (with exit codes)
- Service restarts

## Limitations

- No support for service dependencies
- No support for complex start/stop scenarios
- No built-in file logging support

