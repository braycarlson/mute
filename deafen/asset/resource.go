package main

import (
	"bytes"
	_ "embed"
	"image"
	"os"
	"path/filepath"

	"github.com/tc-hib/winres"
)

var (
	//go:embed undeafen.png
	logo []byte
)

func main() {
	rs := winres.ResourceSet{}

	reader := bytes.NewReader(logo)
	image, _, _ := image.Decode(reader)

	icon, _ := winres.NewIconFromResizedImage(image, nil)
	rs.SetIcon(winres.Name("APPICON"), icon)

	cwd, _ := os.Getwd()
	parent := filepath.Dir(cwd)

	path := filepath.Join(parent, "rsrc_windows_amd64.syso")

	// Create an object file for amd64
	out, _ := os.Create(path)

	defer out.Close()

	rs.WriteObject(out, winres.ArchAMD64)
}
