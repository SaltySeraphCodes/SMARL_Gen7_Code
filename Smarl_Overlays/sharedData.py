from urllib import response
import requests
from requests.exceptions import HTTPError
import datetime
# RACE SPECIFIC DATA
RaceTitle = "Race 4"
RaceLocation = "Road Scrapton"
RaceFormat = " Qualifying" # TODO: Pull booliean from ['meta_data']['qualifying'] as ' Qualifying' or ''
SeasonID = "2" # which season it is to pull sheet data from Make Dynamic?
RaceID = "6" # Make Dynamic?
LeagueTitles = ["A League", "B League"] #TODO: maeke array that displays title based on it
league_id = 1 # [1,2] TODO: remember this affects cars found --NOTICE if cars not showing up or being found
# Sheet name/title (when connected to gsheet)
# Grab Racer Data from Racer Data SHeet
_SpecificRaceData = {"title": RaceTitle, "location": RaceLocation, "format": RaceFormat, "season":SeasonID,"race":RaceID, "league_id":league_id,"leagueTitle":LeagueTitles[league_id-1]}
_Properties = { # various global properties
    "transition_short": 500,
    "transition_shorter": 250,
    "transition_long": 1000,
    "transition_longer": 1300
}
#// replace trrans line: find: .duration(####) replace: .duration("{{properties.transition_longer}}")
# find: yScale(Number(d['id'])) replace: yScale(i + 1) (dont forget to add i to previous function if not there)
#print("sharedData",_SpecificRaceData)
_RacerData = []
SMARL_API_URL = "http://seraphhosts.ddns.net:8080/api" # No longer works due to host migration :(
SMARL_LOCAL_URL = "http://192.168.1.250:8080/api"
IS_LOCAL = True # Remember to change this when you should, Maybe automate this??


def get_smarl_url(): # returns smarl url based on is_local
    if IS_LOCAL: return SMARL_LOCAL_URL
    else: return SMARL_API_URL

## helpers
def formatString(strng): #formats string to have capital and replace stuf
    if strng == None:
        print('bad format string',strng)
        return ''
    output = strng.replace("_"," ")
    output = output.title()
    return output

def getTimefromTimeStr(timeStr):
    #TODO: Time string validation
    minutes = int(timeStr[0:2])
    seconds = int(timeStr[3:5])
    milliseconds = int(timeStr[6:9])
    myTime = datetime.datetime(2019,7,12,1,minutes,seconds,milliseconds)
    return myTime

def setRacerData(data):
    global _RacerData
    _RacerData = data # or append?
    print("Shared Data. setting racer Data",_RacerData)


def getRacerData(): # Only grabs racers in league
    print("Getting racer data")
    all_racers = None
    jsonResponse = None
    try:
        response = requests.get(get_smarl_url() + "/get_all_racers") # in league i
        #response = requests.get(get_smarl_url() + "/get_racers_in_season") # in league i
        #response = requests.get(get_smarl_url() + "/get_racers_in_league")
        response.raise_for_status()
        # access JSOn content
        
        jsonResponse = response.json()

        #print("got racers",jsonResponse,all_racers)
    except HTTPError as http_err:
        print(f'HTTP error occurred: {http_err}')
        return all_racers
    except Exception as err:
        print(f'GRacerdata Other error occurred: {err}')  
        return all_racers
    
    filtered_racers =  [d for d in jsonResponse if int(d['league_id']) >= 0] # all car filter
    #filtered_racers =  [d for d in jsonResponse if int(d['league_id']) == _SpecificRaceData['league_id']] # filter for league
    #TODO: Just grab all racers, doesntt need to be in league, just on map??
    #print("\n\nfiltered racers = ",len(filtered_racers),_SpecificRaceData['league_id'],"\n",filtered_racers)
    all_racers = filtered_racers
    #print("filtered racers",all_racers)
    return all_racers

def getRaceData(): #compiles season and race data
    race_data = None
    #print("Getting race data")
    try:
        response = requests.get(get_smarl_url() + "/get_current_race_data")
        response.raise_for_status()
        # access JSOn content
        jsonResponse = response.json()
        race_data = jsonResponse
    except HTTPError as http_err:
        print(f'HTTP error occurred: {http_err}')
        return race_data
    except Exception as err:
        print(f' GRD Other error occurred: {err}')        # compile owners into racers
        return race_data
    if race_data != None:
        race_data = {"title": "Race " + str(race_data['race_number']) + RaceFormat , "location": formatString(race_data['track']),
        "format": RaceFormat, "season":formatString(race_data['season_name']),"race":str(race_data['race_number']),
         "race_id": race_data['race_id'], "league_id":race_data['league_id'],"leagueTitle":LeagueTitles[league_id-1], "track_id":race_data['track_id'] } #TODO: get_leagueTitle(leagueid)
    #print("returning rd",race_data)
    return race_data


def getTrackData(track_id):
    response = requests.get(get_smarl_url() + "/get_track/"+str(track_id)) # in league i
    response.raise_for_status()
    # access JSOn content    
    jsonResponse = response.json()
    return jsonResponse

def track_record_managment(track_id,fastestLap,fastestRacer):
    #print("Checking for lap record",fastestLap,fastestRacer,track_id)
    track_data = getTrackData(track_id)
    racerID = fastestRacer['id']
    curLapTime = getTimefromTimeStr(fastestLap)

    new_record = False
    if track_data['record'] == None:
        new_record = True
    else:
        oldLapTime = getTimefromTimeStr(track_data['record'])
        if curLapTime < oldLapTime:
            print("New Record Found!",fastestLap,racerID)
            new_record = True
    
    if new_record:
        # upload directly new record data
        resultJson = {"track_id":track_id, "record_holder":racerID, 'record_time':fastestLap}
        try:
            response = requests.post(get_smarl_url() + "/update_track_record",json=resultJson )
            response.raise_for_status()
            jsonResponse = response.json()
            print("Updated Track Record",jsonResponse)
        except HTTPError as http_err:
            print(f'HTTP error occurred: {http_err}')
            return False
        except Exception as err:
            print(f'Other error occurred: {err}')        # compile owners into racers
            return False
    return new_record


def uploadQualResults(race_id,resultBody):
    resultData = None
    resultJson = {"race_id":race_id, "data":resultBody}
    print("uploading results",race_id,resultBody,resultJson)
    #pass #TODO: REMOVE THIS when ready for official race?
    try:
        response = requests.post(get_smarl_url() + "/update_race_qualifying",json=resultJson )
        response.raise_for_status()
        # access JSOn content
        jsonResponse = response.json()
        print("Uploaded Qualifying Data:")
        print(jsonResponse)
        all_racers = jsonResponse ## ??
    except HTTPError as http_err:
        print(f'HTTP error occurred: {http_err}')
        return False
    except Exception as err:
        print(f'Other error occurred: {err}')        # compile owners into racers
        return False
    return True


def uploadResults(race_id,resultBody):
    resultData = None
    resultJson = {"race_id":race_id, "data":resultBody}
    print("uploading results",race_id,resultBody,resultJson)
    #pass #TODO: REMOVE THIS when ready for official race?
    try:
        response = requests.post(get_smarl_url() + "/update_race_results",json=resultJson )
        response.raise_for_status()
        # access JSOn content
        jsonResponse = response.json()
        print("Entire JSON response")
        print(jsonResponse)
        all_racers = jsonResponse
    except HTTPError as http_err:
        print(f'HTTP error occurred: {http_err}')
        return False
    except Exception as err:
        print(f'Other error occurred: {err}')        # compile owners into racers
        return False
    return True


def updateRacerData(): # gets new pull of racer data
    global _RacerData
    _RacerData = getRacerData()
    print("Pulled new racerData",_RacerData)
    

def init():
    global _RacerData
    global _SpecificRaceData
    _RacerData = getRacerData()
    _SpecificRaceData = getRaceData()
    print('sharedData finished init')

#init()
