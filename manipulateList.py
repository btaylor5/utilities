with open("./list.txt") as f:
    o = open("options-list.txt", 'a')
    for line in f:
        line = line.replace('\n', '')
        line = line.strip()
        o.write('<option value="' + line + '">' + line + '</option>\n')
