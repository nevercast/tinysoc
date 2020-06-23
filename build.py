#!/usr/bin/env python
import os 
import sys
from queue import Queue, Empty
from threading import Thread
from subprocess import PIPE, Popen

BUILD_IMAGE = 'build/nevercast_tinysoc_tinysoc_0.1/tinyfpga_bx-icestorm/nevercast_tinysoc_tinysoc_0.1.bin'

RISCV_TOOLCHAIN_PATH = '/opt/riscv32i/bin/'
FIRMWARE_OUTPUT_PATH = 'build/firmware/'
FIRMWARE_IMAGE_NAME = 'firmware'
FIRMWARE_LINKER_SCRIPT = 'firmware/sections.lds'
FIRMWARE_SOURCE = [
  'firmware/start.S',
  'firmware/entry.c'
]

current_prefix = None 
announced_mountpath = False 

def _log_stdout(output_line):
  sys.stdout.write(current_prefix + output_line)

def _log_stderr(output_line):
  sys.stderr.write(current_prefix + output_line)

def _set_subtask(subtask_name, subtask_index=None, subtask_total=None):
  global current_prefix
  if subtask_index is None or subtask_total is None:
    subtask_text = subtask_name
  else:
    subtask_text = '[{}/{}] {}'.format(subtask_index, subtask_total, subtask_name)
  root_task = current_prefix.split(':', 1)[0]
  current_prefix = '{}: {}: '.format(root_task, subtask_text) 

def _thread_queue_output(out, queue):
    for line in iter(out.readline, ''):
      queue.put(line)
    out.close()

def _process_create_output_queues(process):
  out_q, err_q = Queue(), Queue()
  for thread_args in zip((process.stdout, process.stderr), (out_q, err_q)):
    t = Thread(target=_thread_queue_output, args=thread_args)
    t.daemon = True
    t.start()
  return out_q, err_q

def _drain_output_queue(queue, line_handler):
  while True: # breaks on empty 
    try:  
      line_handler(queue.get_nowait())
    except Empty:
        return

def _invoke(*popen_args, interactive=False, **popen_kwargs):
  if interactive: # we perform a passthrough
    process = Popen(*popen_args, stdout=sys.stdout, stderr=sys.stderr, stdin=sys.stdin, text=True, bufsize=1, **popen_kwargs)
    process.wait()
  else: # otherwise, intercept the output and prefix it
    process = Popen(*popen_args, stdout=PIPE, stderr=PIPE, text=True, bufsize=1, **popen_kwargs)
    q_stdout, q_stderr = _process_create_output_queues(process)
    while process.poll() is None:
      _drain_output_queue(q_stdout, _log_stdout)
      _drain_output_queue(q_stderr, _log_stderr)
    _drain_output_queue(q_stdout, _log_stdout)
    _drain_output_queue(q_stderr, _log_stderr)
  return process 

def _invoke_container(container_name, container_command=None, **invoke_kwargs):
  global announced_mountpath
  absolute_path = os.path.abspath(os.getcwd())
  if not announced_mountpath:
    _log_stdout('Mounting {} to /workspace in container.\n'.format(absolute_path))
    announced_mountpath = True
  if container_command is not None:
    if isinstance(container_command, (list, tuple)):
      extra_args = list(container_command)
    else:
      command_str = str(container_command)
      if ' ' in command_str:
        extra_args = command_str.split(' ')
      else:
        extra_args = [command_str]
    return _invoke(['docker', 'run', '--rm', '-it', '-v', '{}:/workspace'.format(absolute_path), container_name] + extra_args, **invoke_kwargs) 
  else:
    return _invoke(['docker', 'run', '--rm', '-it', '-v', '{}:/workspace'.format(absolute_path), container_name], **invoke_kwargs) 

def check_process(process, okay_exitcodes=(0,)):
  if process.returncode is None:
    return # maybe this is actual a code error?
  if process.returncode not in okay_exitcodes:
    _log_stderr('Process failed to exit cleanly, errno: {}\n'.format(process.returncode))
    sys.exit(process.returncode)
  else: # Don't log anything, it's noisy
    pass

def cmd_interactive(**parameters):
  container_name = parameters['container_name']
  check_process(_invoke_container(container_name, interactive=True))

def cmd_build(**parameters):
  container_name = parameters['container_name']
  check_process(_invoke_container(container_name, 'fusesoc run --target=tinyfpga_bx nevercast:tinysoc:tinysoc'))

def cmd_program(**parameters):
  check_process(_invoke(['tinyprog', '-p', BUILD_IMAGE, '-u', FIRMWARE_OUTPUT_PATH + FIRMWARE_IMAGE_NAME + '.bin']))

def cmd_test(**parameters):
  container_name = parameters['container_name']
  check_process(_invoke_container(container_name, 'fusesoc run --target=sim nevercast:tinysoc:tinysoc'))

def cmd_compile(**parameters):
  container_name = parameters['container_name']
  _set_subtask('init', 1, 3)
  check_process(
    _invoke(['mkdir', '-p', FIRMWARE_OUTPUT_PATH])
  )
  _set_subtask('gcc', 2, 3)
  check_process(
    _invoke_container(container_name, 
      '{riscv_toolchain}riscv32-unknown-elf-gcc -v -march=rv32imc -nostartfiles -Wl,-Bstatic,-T,{sections},--strip-debug,-Map={output_path}{image_name}.map,--cref -ffreestanding -nostdlib -o {output_path}{image_name}.elf {sources}'.format(
        riscv_toolchain=RISCV_TOOLCHAIN_PATH,
        output_path=FIRMWARE_OUTPUT_PATH,
        sections=FIRMWARE_LINKER_SCRIPT,
        image_name=FIRMWARE_IMAGE_NAME,
        sources=' '.join(FIRMWARE_SOURCE)
      )
    )
  )
  _set_subtask('objcopy', 3, 3)
  check_process(
    _invoke_container(container_name, 
      '{riscv_toolchain}riscv32-unknown-elf-objcopy -v -O binary {output_path}{image_name}.elf {output_path}{image_name}.bin'.format(
        riscv_toolchain=RISCV_TOOLCHAIN_PATH,
        output_path=FIRMWARE_OUTPUT_PATH,
        image_name=FIRMWARE_IMAGE_NAME
      )
    )
  )

def help(executable):
  print('! tinysoc build script !')
  print('parameters:')
  print('  container_name :: The name of the Docker container to use, default: nevercast/tinysoc:latest')
  print('  clk_freq_hz    :: Clock frequency to use for simulation and hardware builds, default: 16MHz')
  print('commands:')
  print('  interactive    :: Start an interactive container and open shell')
  print('  compile        :: Compile tinysoc firmware into a flashable image')
  print('  build          :: Build a tinysoc hardware image for the TinyFPGA')
  print('  program        :: Program the last built image to the TinyFPGA')
  print('  test           :: Simulate the test bench')
  print('usage:')
  print('{} [parameter=value]... COMMAND [COMMANDS]...'.format(executable))
  print('example: Build, Test and Program the TinyFPGA with tinysoc, using default parameters')
  print('{} build test program'.format(executable))
  print('! end of help !')

def main():
  global current_prefix
  executable, *arguments = sys.argv
  if len(arguments) == 0:
    help(executable)
    return

  parameters = {
    'container_name': 'nevercast/tinysoc:latest',
    'clk_freq_hz': 16_000_000
  }
  parameter_types = {
    'container_name': str, 
    'clk_freq_hz': int 
  }
  command_chain = []
  valid_commands = [
    'interactive', 'build', 'program', 'test', 'compile'
  ]

  for argument in arguments:
    if '=' in argument:
      key, value = argument.split('=', 1)
      if key not in parameters:
        help(executable)
        print('Parameter {} is not defined. Aborting.'.format(key))
        return 
      # TODO(josh): Experiment or implement in the future, not sure if I'll want this
      if key == 'clk_freq_hz':
        print('clk_freq_hz parameter is not implemented, sorry! Aborting.')
        return
      # /TODO
      parameters[key] = parameter_types[key](value)
    elif argument in valid_commands:
      if argument in command_chain:
        help(executable)
        print('Command {} was already specified earlier in the chain. Aborting.'.format(argument))
        return 
      else:
        command_chain.append(argument)
    else:
      help(executable)
      print('Argument {} was not understood. Aborting.'.format(argument))
      return 
  
  if not command_chain:
    help(executable)
    print('No commands were specified. Aborting.')
    return 

  for index, command in enumerate(command_chain):
    current_prefix = '[{}/{}] {}: '.format(index + 1, len(command_chain), command)
    _log_stdout('Begin {}\n'.format(command))
    globals()['cmd_{}'.format(command)](**parameters)

if __name__ == '__main__':
  main()