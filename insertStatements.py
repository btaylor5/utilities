with open("/home/btaylor5/src/remove.txt") as f:
    o = open("InsertScript.txt", 'a')
    for line in f:
        line = line.replace('\n', '')
        o.write('INSERT INTO keywords (keyword) VALUES (\'' + line + '\');\n')
