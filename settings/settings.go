package settings

import (
	"log"
	"os"
	"path/filepath"

	"github.com/go-ini/ini"
)

type (
	Settings struct {
		Capture string
		Render  string
	}
)

func NewSettings() *Settings {
	var directory, _ = os.UserConfigDir()
	var home = filepath.Join(directory, "mute")
	var path = filepath.Join(home, "settings.ini")

	var err error

	err = os.MkdirAll(home, os.ModePerm)

	if err != nil {
		log.Printf("Unable to create directory: %v", err)
		return &Settings{}
	}

	if _, err = os.Stat(path); os.IsNotExist(err) {
		var file *os.File
		file, err = os.Create(path)

		if err != nil {
			log.Printf("Unable to create file: %v", err)
			return &Settings{}
		}

		file.Close()

		var configuration *ini.File
		configuration = ini.Empty()
		configuration.NewSection("capture")
		configuration.Section("capture").NewKey("name", "Microphone")
		// configuration.Section("capture").NewKey("volume", "70")

		configuration.NewSection("render")
		configuration.Section("render").NewKey("name", "Speaker")
		// configuration.Section("render").NewKey("volume", "30")

		err = configuration.SaveTo(path)

		if err != nil {
			log.Printf("Unable to save settings: %v", err)
			return &Settings{}
		}
	}

	var configuration *ini.File

	configuration, err = ini.Load(path)

	if err != nil {
		log.Printf("Unable to load settings: %v", err)
		return &Settings{}
	}

	var capture *ini.Section
	capture = configuration.Section("capture")

	var cname string
	cname = capture.Key("name").String()

	var render *ini.Section
	render = configuration.Section("render")

	var rname string
	rname = render.Key("name").String()

	return &Settings{
		Capture: cname,
		Render:  rname,
	}
}
