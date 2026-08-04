import re,pathlib

gamename = "super_pacman"

# game_specific: replace or remove I/O addresses
# if not done it will write in ROM here!!
sound_mem_regex = re.compile("\w+_(40[45]\w)")
store_to_video = re.compile("GET_ADDRESS\s+0x0")

input_dict = {"system_3300":"read_system_inputs",
"watchdog_8000":"",
"video_stuff_5009" : "",
"video_stuff_5008" : "",
"video_stuff_5002" : "",
"video_stuff_5003" : "",
"video_stuff_5004" : "",
"video_stuff_500b" : "",
"video_stuff_500a" : ""


}

tablere = re.compile("move.w\t#(\w*jump_table_....),d(.)")
jmpre = re.compile("(j..)\s+\[([ab]),(.)\]")

# empty template
##single_line_to_cc_protect = set()
##remove_error_in_next_line = set()
##remove_error_in_prev_line = set()
##line_to_push_cc_protect = set() | single_line_to_cc_protect
##line_to_pull_cc_protect = set() | single_line_to_cc_protect
##line_to_pull_cc_prev_protect = set()

single_line_to_cc_protect = {0xe5bc,0xe5ce,0xfdb5}
remove_error_in_next_line = {0xf6c1,0xfa25,0xfa2a,0xe5ba,0xe5be,0xe5cc,0xe5d0,0xfae9,0xfdb7,0xe2b4,0Xe2bb,0xe2c4}
remove_error_in_prev_line = set()
line_to_push_cc_protect = {0xfae2} | single_line_to_cc_protect
line_to_pull_cc_protect = {0xfae7} | single_line_to_cc_protect
line_to_pull_cc_prev_protect = set()

def game_specific(address,lines,i):
    line = lines[i]
    # game_specific
    if address in {0xc78a,0xec4c}:
        # strange protection ?
        line = change_instruction("jra\tindirect_jump_10e4",lines,i)
    elif address == 0xf6c3:
        line += "\tSET_XC_FLAGS\n"
    elif address == 0xfa25:
        line = remove_instruction(lines,i)
    elif address == 0xfa2a:
        line = "\tcmp.b\t#0x21,d0\n"+line
    elif address == 0xe326:
        line = change_instruction("rts",lines,i)
    elif address == 0xfb43:
        lines[i+1] = "\tSET_X_FROM_CLEARED_C\n"
    elif "[indirect_jump]" in line:
        m = jmpre.search(line)
        if m:
            ireg = m.group(2).upper()  # A or B
            inst = m.group(1).upper()
            reg = {"x":"A2","y":"A3","u":"A4"}[m.group(3)]
            rest = re.sub(".*\"","",line)
            nb_cases = int(line.split("nb_entries=")[1].strip(']\n'))
            line = f"\t{inst}_{ireg}_INDEXED\t{reg},{nb_cases}{rest}"
        elif "[$04,u]" in line:
            line = change_instruction("jbsr\tjump_u_plus_4",lines,i)
    # call tree manipulation functions
    elif address in {0xe2b6,0Xe2c1,0xe2c6}:
        line = change_instruction("move.l\td2,(4,sp)",lines,i)
    elif address == 0xe2bd:
        line = "\tMAKE_D\n"+change_instruction("move.w\td1,(8,sp)",lines,i)
    elif address in {0xe2b8,0Xe2bf}:
        line = remove_instruction(lines,i)

    elif "had to be swapped" in line:
        line = ""

    line = re.sub(tablere,subt,line)
    return line

store_to_video = re.compile("GET_ADDRESS\s+(0x8\w\w\w|video_ram_d)",flags=re.I)   # game_specific





def remove_continuing_lines(lines,i):
    for j in range(i+1,i+4):
        if "[...]" in lines[j]:
            lines[j] = ""
        else:
            break


def get_line_address(line):
    try:
        toks = line.split("|")
        address = toks[1].strip(" [$").split(":")[0]
        return int(address,16)
    except (ValueError,IndexError):
        return None

def remove_continuing_lines(lines,i):
    for j in range(i+1,i+4):
        if "[...]" in lines[j]:
            lines[j] = ""
        else:
            break


def change_instruction(code,lines,i,continuing_lines=True):
    line = lines[i]
    toks = line.split("|")
    if len(toks)==2:
        toks[0] = f"\t{code}"
        if continuing_lines:
            remove_continuing_lines(lines,i)
        return " | ".join(toks)
    return line

def remove_error(line,ignore=False):
    if "ERROR" in line:
        return ""
    elif not ignore:
        raise Exception(f"No ERROR to remove in {line}")
    else:
        return line
def remove_instruction(lines,i,continuing_lines=True):
    return change_instruction("",lines,i,continuing_lines=continuing_lines)

def remove_continuing_lines(lines,i):
    for j in range(i+1,i+4):
        if "[...]" in lines[j]:
            lines[j] = ""
        else:
            break



def process_jump_table(line):

    m = re.search("\[nb_entries=(\d+)",line)
    if m:
        nb_entries = m.group(1)
        line = f"""\t.ifndef\tRELEASE
\tmove.w\t#{nb_entries},d7
\t.endif
"""+line

    return line

def get_original_instruction(line):
    toks = line.split("| [")
    if len(toks)==1:
        return ""
    inst = toks[1][7:].split("]")[0]
    return inst


def remove_code(pattern,lines,i):
    if pattern in lines[i]:
        lines[i] = remove_instruction(lines,i)
        remove_continuing_lines(lines,i)
    return lines[i]

def rebuild_lines(lines):
    return "".join(lines).splitlines(True)

def swap_lines(lines,i,j):
    lines[i],lines[j] = lines[j].rstrip()+ "| swapped\n",lines[i].rstrip()+ "| swapped\n"
    return lines[i]

def kill_code(lines,start_line,end_address):
    while True:
        address = get_line_address(lines[start_line])
        lines[start_line] = remove_instruction(lines,start_line)
        if "|" not in lines[start_line]:
            lines[start_line] = ""
        if address == end_address:
            break
        start_line+=1

def subt(m):
    tn = m.group(1)
    rn = m.group(2)
    offset = tn.split("_")[-1]
    rval = f"""
\t.ifndef\tRELEASE
\tmove.w\t#0x{offset},d{rn}
\t.endif
\tlea\t{tn},a{rn}"""
    return rval

equates = []
global_symbols = []
equates_re = re.compile("(\w+)\s*=\s*(\$?\w+)")
this_dir = pathlib.Path(__file__).absolute().parent

source_dir = this_dir / "../src"


# various dirty but at least automatic patches applying on the converted code
with open(source_dir / "conv.s") as f:
    lines = list(f)

    for i,line in enumerate(lines):
        m = equates_re.match(line)
        if m:
            equates.append(line)
            line = ""


##        elif "review stray daa" in line:
##            line = """\tCLR_XC_FLAGS
##\tmove.b\t(a0),d6
##\tabcd\td6,d0
##"""
        address = get_line_address(line)


        if "[return]" in line:
            if "MAKE_" in line:
                line = ""
            else:
                line = change_instruction("rts",lines,i)

        elif "[nop]" in line:
            line = remove_instruction(lines,i)

        elif "[push_function]" in line:
            toks = line.split()
            line = remove_instruction(lines,i)
            pa = toks[1].strip("#")
            lines[i+1] = change_instruction(f"pea\t{pa}",lines,i+1)
        elif "[breakpoint]" in line and address:
            line = f'\tBREAKPOINT "{address:04x}"\n{line}'

        elif "[cc_ok]" in line:
            if "rts" in line and "ret]" not in line: # conditional return
                lines[i-1] = remove_error(lines[i-1],True)
            else:
                lines[i+1] = remove_error(lines[i+1],True)


        line = process_jump_table(line)


        # pre-add video_address tag if we find a store instruction to an explicit 3000-3FFF address
        # pre-add video_address tag if we find a store instruction to an explicit 3000-3FFF address
        if store_to_video.search(line):
            line = line.rstrip() + " [video_address]\n"


        if "[unchecked_address" in line:
            line = line.replace("_ADDRESS","_UNCHECKED_ADDRESS")
        if "[video_address" in line:
            # give me the original instruction
            line = line.replace("_ADDRESS","_UNCHECKED_ADDRESS")
            # if it's a write, insert a "VIDEO_DIRTY" macro after the write
            for j in range(i+1,len(lines)):
                next_line = lines[j]
                if "[...]" not in next_line:
                    break
                if ",(a0)" in next_line or "clr" in next_line or "MOVE_W_FROM_REG" in next_line:
                    if any(x in next_line for x in ["address_word","MOVE_W_FROM_REG"]):
                        lines[j] = next_line+"\tVIDEO_WORD_DIRTY | [...]\n"
                    else:
                        lines[j] = next_line+"\tVIDEO_BYTE_DIRTY | [...]\n"
                    break



        if "[pop_stack]" in line:
            line = change_instruction("addq\t#4,sp",lines,i)

        ###############################################
        line = game_specific(address,lines,i)

        ###############################################
        if address in remove_error_in_prev_line:
            lines[i-1] = remove_error(lines[i-1].strip()+f" ({address:04x})")
        if address in remove_error_in_next_line:
            lines[i+1] = remove_error(lines[i+1].strip()+f" ({address:04x})")
        if address in line_to_pull_cc_protect:
            # protect the sub instructions if any
            for j in range(i+1,len(lines)):
                if not "[...]" in lines[j]:
                    break

            lines[j-1] += "\tPOP_SR\n"
            if j-1==i:
                line = lines[i]

        if "[function_address]" in line:
            # we have to patch this code as it takes an immediate value which
            # is actually an address
            inst,arg = line.split("|")[1].strip().strip("[]").split(":")[1].split("]")[0].split()
            if inst!="ldd" or ",d1" in line:
                if inst=="cmpx":
                    line = change_instruction(f'BREAKPOINT\t"{address:04x}"',lines,i)
                else:
                    dest_reg = {"d":"d1","u":"d4","x":"d2","y":"d3"}[inst[2]]  # d,u,x
                    dest_addr = arg[2:]
                    line = change_instruction(f"move.l\t#l_{dest_addr},{dest_reg}",lines,i)
                    line += f"\tENCODE_ADDRESS\t{dest_reg},{dest_reg}\n"
                    if inst=="ldd" and "MAKE_D" in lines[i+1]:
                        lines[i+1] = ""

        if address in line_to_push_cc_protect:
            # protect the sub instructions
            line = "\tPUSH_SR\n"+line
        if address in line_to_pull_cc_prev_protect:
            # protect the sub instructions
            line = "\tPOP_SR\n"+line

        if "GET_ADDRESS" in line:
            val = line.split()[1].split(",")[0]
            osd_call = input_dict.get(val)
            if osd_call is not None:

                if osd_call:
                    if isinstance(osd_call,list):
                        # choose depending on read/write
                        if "a,(" in line:
                            osd_call = osd_call[1]
                        else:
                            osd_call = osd_call[0]
                    if osd_call:
                        line = change_instruction(f"jbsr\tosd_{osd_call}",lines,i)
                    else:
                        line = remove_instruction(lines,i)
                else:
                    line = remove_instruction(lines,i)
                lines[i+1] = remove_instruction(lines,i+1)

        if "[global]" in line:
            label = line.split(":")[0]
            global_symbols.append(label)

        lines[i] = line

    # remove duplicate VIDEO_BYTE_DIRTY
    lines = rebuild_lines(lines)
    new_lines = []
    prev_line = ""
    for line in lines:
        if "VIDEO_BYTE_DIRTY" in line and "VIDEO_BYTE_DIRTY" in prev_line:
            pass
        else:
            new_lines.append(line)
        prev_line = line

with open(source_dir / "data.inc","w") as fw:
    fw.writelines(equates)

with open(source_dir / f"{gamename}.68k","w") as fw:

    fw.write(f"""\t.include "data.inc"
""")
    for g in global_symbols:
        fw.write(f"\t.global\t{g}\n")

    fw.writelines(new_lines)

    fw.write("""
indirect_jump_10e4:
\tGET_ADDRESS\t0x10e4
\tmove.w\t(a0),d6
\tBREAKPOINT\t"indirect jmp check d6"
\tillegal

jump_u_plus_4:
\tGET_REG_ADDRESS\t4,d4
\tmove.w\t(a0),d6
\tBREAKPOINT\t"indirect jmp check d4"
\tillegal


play_sound:
    move.l  d0,-(a7)
    move.l  a0,d0
    sub.l   a6,d0
    sub.w   #0x4040,d0
    jbsr    osd_sound_start
    move.l  (a7)+,d0
    rts


sound_control:
    tst.b   d0
    jeq     0f
    jbra    play_sound
0:
    * we should stop the sound, but it actually isn't
    * needed, and doing so would stop the music
    rts

""")