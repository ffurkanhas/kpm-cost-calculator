package com.kpm.costcalculator.core;

import java.io.File;
import java.io.FileNotFoundException;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Scanner;
import java.util.StringTokenizer;

enum Axis {
    /**
     * Extruder
     */
    E,
    /**
     * Define speed in mm/min
     */
    F,
    /**
     * X axis
     */
    X,
    /**
     * Y axis
     */
    Y,
    /**
     * Z axis
     */
    Z
}

public class GCodeAnalyzer {

    public Estimative estimate(String filename) throws FileNotFoundException {
        System.out.println("Analyzing " + filename);

        File source = new File(filename);
        Scanner scanner = new Scanner(source);

        Estimative estimative = new Estimative();
        estimative.name = source.getName();

        double speed = 0;
        double x0 = 0;
        double y0 = 0;
        double z0 = 0;
        double e0 = 0;

        while (scanner.hasNextLine()) {
            String line = scanner.nextLine();
            double deltae = 0;

            if (line.startsWith("G92 ")) {
                line = line.replaceAll(";.*", ""); //comments

                StringTokenizer st = new StringTokenizer(line.substring(3));
                while (st.hasMoreTokens()) {

                    String token = st.nextToken();
                    Axis axis = Axis.valueOf(token.substring(0, 1));

                    switch (axis) {
                        case E:
                            e0 = 0;
                            break;
                        case X:
                            x0 = 0;
                            break;
                        case Y:
                            y0 = 0;
                            break;
                        case Z:
                            z0 = 0;
                            break;
                    }

                }
            }

            if (line.startsWith("G1 ")) {
                line = line.replaceAll(";.*", ""); //comments

                BigDecimal distance = BigDecimal.ZERO;

                StringTokenizer st = new StringTokenizer(line.substring(3));
                while (st.hasMoreTokens()) {

                    String token = st.nextToken();
                    Axis axis = Axis.valueOf(token.substring(0, 1));
                    double value = Double.valueOf(token.substring(1));

                    switch (axis) {
                        case E:
                            deltae = value - e0;
                            e0 = value;
                            break;

                        case F:
                            speed = value;
                            break;

                        case X:
                            double deltax = value - x0;
                            x0 = value;

                            token = st.nextToken();
                            value = Double.valueOf(token.substring(1));

                            double deltay = value - y0;
                            y0 = value;

                            distance = new BigDecimal(Math.sqrt(deltax * deltax + deltay * deltay));
                            break;

                        case Z:
                            double deltaZ = value - z0;
                            z0 = value;
                            distance = new BigDecimal(deltaZ);
                            break;
                    }
                }

                //In case it's only extruding
                distance = distance.max(new BigDecimal(deltae));

                BigDecimal time = distance.divide(new BigDecimal(speed), 3, RoundingMode.HALF_UP);
                estimative.time = estimative.time.add(time);
            }

            //Slic3r

            if (line.startsWith("; filament used")) {
                if (line.contains("cm3")) {
                    String[] values = splitValues(line, "=");
                    String[] dimensions = values[1].split("\\(");
                    estimative.length = new BigDecimal(dimensions[0].replace("mm", ""));
                    estimative.volume = new BigDecimal(dimensions[1].replace("cm3", "").replace(")", ""));
                } else {
                    estimative.weight = new BigDecimal(splitValues(line, "=")[1].replace("g", ""));
                }
            }


            if (line.startsWith(";   Plastic weight")) {
                String valueString = line.replace(";   Plastic weight: ", "").split(" ")[0];
                estimative.weight = new BigDecimal(valueString);
            }

            if (line.startsWith(";   Plastic volume")) {
                String valueString = line.replace(";   Plastic volume: ", "").split(" ")[0];
                estimative.volume = new BigDecimal(valueString).divide(new BigDecimal(10), 2, RoundingMode.HALF_UP);
            }

            if (line.startsWith(";   Filament length")) {
                String valueString = line.replace(";   Filament length: ", "").split(" ")[0];
                estimative.length = new BigDecimal(valueString);
            }

            if (line.startsWith(";   Build time")) {
                estimative.time = BigDecimal.ZERO;
                String valueString = line.replace(";   Build time: ", "");
                StringTokenizer st = new StringTokenizer(valueString);
                while(st.hasMoreTokens()) {
                    BigDecimal time = new BigDecimal(st.nextToken());
                    String type = st.nextToken();
                    if(type.equals("hour") || type.equals("hours")) {
                        time = time.multiply(new BigDecimal(60));
                    }
                    estimative.time = estimative.time.add(time);
                }

            }
        }

        scanner.close();

        System.out.println(estimative);

        return estimative;
    }

    private String[] splitValues(String line, String character) {
        return line.replaceAll("[; \\)]", "").split(character);
    }

}