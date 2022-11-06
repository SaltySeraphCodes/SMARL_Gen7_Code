from pynput import keyboard
#very hard coded and not dynamic because yolo
def on_press(key):
    #print(key)
    try:
        result = key.char
        if key.char == "=": #TODO also read mousebuttond 3 and 4
            #print("zooming in")
            output =  "{\"zoomIn\": \"true\", \"zoomOut\": \"false\"}"
            print("Writing  "+" - " +output)
            with open('zoomControls.json', 'w') as outfile:
                outfile.write(output)

        if key.char == "-":
            #print("zoom out")
            output =  "{\"zoomIn\": \"false\", \"zoomOut\": \"true\"}"
            print("Writing  "+" - " +output)
            with open('zoomControls.json', 'w') as outfile:
                outfile.write(output)
       
        if key.char == "/":
            output =  "{\"command\": \"cMode\", \"value\": \"0\"}"
            print("Writing  "+" - " +output)
            with open('cameraInput.json', 'w') as outfile:
                outfile.write(output)
       
        if key.char == "*":
            output =  "{\"command\": \"exit\", \"value\": \"0\"}"
            print("Writing  "+" - " +output)
            with open('cameraInput.json', 'w') as outfile:
                outfile.write(output)

        if key.char == "[":
            output =  "{\"command\": \"focusCycle\", \"value\": \"-1\"}"
            print("Writing  "+" - " +output)
            with open('cameraInput.json', 'w') as outfile:
                outfile.write(output)
        if key.char == "]":
            output =  "{\"command\": \"focusCycle\", \"value\": \"1\"}"
            print("Writing  "+" - " +output)
            with open('cameraInput.json', 'w') as outfile:
                outfile.write(output)

        if key.char == ";":
            output =  "{\"command\": \"camCycle\", \"value\": \"-1\"}"
            print("Writing  "+" - " +output)
            with open('cameraInput.json', 'w') as outfile:
                outfile.write(output)
        if key.char == "'":
            output =  "{\"command\": \"camCycle\", \"value\": \"1\"}"
            print("Writing  "+" - " +output)
            with open('cameraInput.json', 'w') as outfile:
                outfile.write(output)

    except:
        #print(key)
        if key == keyboard.Key.end:
            print("Exiting")
            return False
        pass
   
def on_release(key):
    try:
        result = key.char
        if key.char == "=":
            output =  "{\"zoomIn\": \"false\", \"zoomOut\": \"false\"}"
            print("Writing  "+" - " +output)
            with open('zoomControls.json', 'w') as outfile:
                outfile.write(output)

        if key.char == "-":
            output =  "{\"zoomIn\": \"false\", \"zoomOut\": \"false\"}"
            print("Writing  "+" - " +output)
            with open('zoomControls.json', 'w') as outfile:
                outfile.write(output)
    except:
        pass 
    
    #if key == keyboard.Key.esc:
    #    # Stop listener
    #    return False


# Collect events until released
with keyboard.Listener(
        on_press=on_press,
        on_release=on_release) as listener:
    listener.join()